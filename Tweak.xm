#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>

/*
 * GlassFolders 0.7.1 Beta 1.1 — Safe Optical
 *
 * Stable scope:
 * - closed SpringBoard folder icons only
 * - no opened-folder private hierarchy modification
 *
 * Optical model:
 * - CABackdropLayer for wallpaper color / blur / saturation
 * - cached rounded-rect SDF lighting
 * - upper-left neutral-white filament + core + soft shoulder
 * - independent right/bottom secondary rim
 *
 * No daemon / DisplayLink / Timer / gyroscope / Metal render loop.
 */

static CFStringRef const GFPreferencesDomain = CFSTR("com.local.glassfolders");

static BOOL GFEnabled = YES;
static NSInteger GFStyle = 0;          // 0 Clear, 1 Liquid Glass
static CGFloat GFGlassStrength = 0.0;  // 0.0 ... 1.0

static BOOL GFReadBool(CFStringRef key, BOOL fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, GFPreferencesDomain);
    if (!value) return fallback;

    BOOL result = fallback;

    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int n = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &n);
        result = (n != 0);
    }

    CFRelease(value);
    return result;
}

static NSInteger GFReadInteger(CFStringRef key, NSInteger fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, GFPreferencesDomain);
    if (!value) return fallback;

    long long n = fallback;

    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &n);
    }

    CFRelease(value);
    return (NSInteger)n;
}

static CGFloat GFReadPercent(CFStringRef key, CGFloat fallbackPercent) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, GFPreferencesDomain);

    if (!value) {
        return MIN(1.0, MAX(0.0, fallbackPercent / 100.0));
    }

    double n = fallbackPercent;

    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &n);
    }

    CFRelease(value);
    return MIN(1.0, MAX(0.0, (CGFloat)n / 100.0));
}

static void GFLoadPreferences(void) {
    CFPreferencesAppSynchronize(GFPreferencesDomain);

    GFEnabled = GFReadBool(CFSTR("Enabled"), YES);
    GFStyle = GFReadInteger(CFSTR("Style"), 0);
    GFGlassStrength = GFReadPercent(CFSTR("GlassStrength"), 0.0);

    if (GFStyle < 0 || GFStyle > 1) {
        GFStyle = 0;
    }
}


/*
 * Avoid linking private classes directly.
 * Both CABackdropLayer and CAFilter are resolved at runtime.
 */
static id GFCreateCAFilter(NSString *type) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL selector = NSSelectorFromString(@"filterWithType:");

    if (!filterClass || ![filterClass respondsToSelector:selector]) {
        return nil;
    }

    IMP imp = [filterClass methodForSelector:selector];
    typedef id (*GFFilterFactoryIMP)(id, SEL, id);
    GFFilterFactoryIMP func = (GFFilterFactoryIMP)imp;
    return func(filterClass, selector, type);
}


static inline CGFloat GFClamp01(CGFloat value) {
    return MIN(1.0, MAX(0.0, value));
}

static inline CGFloat GFRoundedRectSDF(CGFloat x,
                                      CGFloat y,
                                      CGFloat width,
                                      CGFloat height,
                                      CGFloat radius) {
    CGFloat halfW = width * 0.5;
    CGFloat halfH = height * 0.5;

    radius = MAX(0.0, MIN(radius, MIN(halfW, halfH)));

    CGFloat qx =
        fabs(x - halfW) - (halfW - radius);
    CGFloat qy =
        fabs(y - halfH) - (halfH - radius);

    CGFloat outsideX = MAX(qx, 0.0);
    CGFloat outsideY = MAX(qy, 0.0);

    CGFloat outside = hypot(outsideX, outsideY);
    CGFloat inside = MIN(MAX(qx, qy), 0.0);

    return outside + inside - radius;
}

static NSCache *GFOpticalLightingCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 24;
        cache.totalCostLimit = 20 * 1024 * 1024;
    });

    return cache;
}

/*
 * Generate a static optical-lighting texture.
 *
 * This is NOT a blurred stroke and NOT a diagonal gradient.
 *
 * Each pixel derives from:
 * - distance to the rounded edge,
 * - local edge normal,
 * - fixed upper-left light direction.
 *
 * Therefore the rounded corner naturally carries the highlight through it.
 */
static UIImage *GFCreateOpticalLightingImage(CGSize size,
                                             CGFloat cornerRadius,
                                             CGFloat strength) {
    if (size.width < 2.0 || size.height < 2.0) return nil;

    CGFloat renderScale = MIN(UIScreen.mainScreen.scale, 3.0);
    size_t pixelWidth = (size_t)MAX(2.0, floor(size.width * renderScale + 0.5));
    size_t pixelHeight = (size_t)MAX(2.0, floor(size.height * renderScale + 0.5));
    NSInteger strengthStep = MAX(0, MIN(20, (NSInteger)lround(strength * 20.0)));

    NSString *cacheKey = [NSString stringWithFormat:@"C-%zux%zu-r%.2f-s%ld",
        pixelWidth, pixelHeight, cornerRadius, (long)strengthStep];

    NSCache *cache = GFOpticalLightingCache();
    UIImage *cached = [cache objectForKey:cacheKey];
    if (cached) return cached;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = pixelWidth * 4;
    CGContextRef context = CGBitmapContextCreate(
        NULL, pixelWidth, pixelHeight, 8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;

    unsigned char *pixels = (unsigned char *)CGBitmapContextGetData(context);
    if (!pixels) { CGContextRelease(context); return nil; }

    CGFloat width = (CGFloat)pixelWidth;
    CGFloat height = (CGFloat)pixelHeight;
    CGFloat radius = MAX(0.0, cornerRadius * renderScale);
    CGFloat e = sqrt(GFClamp01(strength));

    /* Upper-left: filament -> core -> soft shoulder. */
    CGFloat shoulderWidth = (4.8 + 1.8 * e) * renderScale;
    CGFloat coreWidth = (0.90 + 0.30 * e) * renderScale;
    CGFloat filamentWidth = (0.35 + 0.10 * e) * renderScale;

    CGFloat highlightShoulderGain = 0.052 + 0.014 * e;
    CGFloat highlightCoreGain = 0.125 + 0.030 * e;
    CGFloat highlightFilamentGain = 0.190 + 0.045 * e;

    /*
     * Right/bottom Alook-style secondary rim.
     * Bright rim stays at the edge; darker shoulder begins farther inside.
     */
    CGFloat baseEdgeGain = 0.008 + 0.003 * e;
    CGFloat secondaryRimWidth = (0.55 + 0.12 * e) * renderScale;
    CGFloat secondaryRimGain = 0.095 + 0.022 * e;

    CGFloat shadowCenter = (2.20 + 0.40 * e) * renderScale;
    CGFloat shadowWidth = (1.60 + 0.30 * e) * renderScale;
    CGFloat shadowGain = 0.012 + 0.004 * e;

    const CGFloat invSqrt2 = 0.70710678118;
    CGFloat lightX = -invSqrt2;
    CGFloat lightY = -invSqrt2;
    CGFloat epsilon = MAX(0.65, renderScale * 0.55);

    for (size_t py = 0; py < pixelHeight; py++) {
        for (size_t px = 0; px < pixelWidth; px++) {
            CGFloat x = (CGFloat)px + 0.5;
            CGFloat y = (CGFloat)py + 0.5;

            CGFloat sdf = GFRoundedRectSDF(x, y, width, height, radius);
            CGFloat aaWidth = MAX(0.85, renderScale * 0.72);
            CGFloat edgeCoverage = GFClamp01(0.5 - sdf / aaWidth);
            if (edgeCoverage <= 0.001) continue;

            CGFloat insideDepth = MAX(0.0, -sdf);

            CGFloat u = x / MAX(1.0, width);
            CGFloat v = y / MAX(1.0, height);
            CGFloat diagonal = GFClamp01(1.0 - (u + v) * 0.5);

            /* Only a broad light direction; never a diagonal white stripe. */
            CGFloat signedLight =
                pow(diagonal, 2.60) * 0.0040 -
                pow(1.0 - diagonal, 2.80) * 0.0030;

            CGFloat maxBand = MAX(
                shoulderWidth * 3.0,
                shadowCenter + shadowWidth * 3.0
            );

            if (insideDepth <= maxBand) {
                CGFloat dx =
                    GFRoundedRectSDF(x + epsilon, y, width, height, radius) -
                    GFRoundedRectSDF(x - epsilon, y, width, height, radius);
                CGFloat dy =
                    GFRoundedRectSDF(x, y + epsilon, width, height, radius) -
                    GFRoundedRectSDF(x, y - epsilon, width, height, radius);

                CGFloat normalLength = hypot(dx, dy);
                if (normalLength > 0.0001) {
                    CGFloat nx = dx / normalLength;
                    CGFloat ny = dy / normalLength;

                    CGFloat ndotl = nx * lightX + ny * lightY;
                    CGFloat facing = MAX(0.0, ndotl);
                    CGFloat opposite = MAX(0.0, -ndotl);

                    CGFloat shoulderRatio = insideDepth / MAX(0.001, shoulderWidth);
                    CGFloat coreRatio = insideDepth / MAX(0.001, coreWidth);
                    CGFloat filamentRatio = insideDepth / MAX(0.001, filamentWidth);
                    CGFloat secondaryRatio = insideDepth / MAX(0.001, secondaryRimWidth);

                    CGFloat shoulder = exp(-(shoulderRatio * shoulderRatio));
                    CGFloat core = exp(-(coreRatio * coreRatio * 1.35));
                    CGFloat filament = exp(-pow(filamentRatio, 2.65));
                    CGFloat secondaryFilament = exp(-pow(secondaryRatio, 2.35));

                    CGFloat white =
                        filament * baseEdgeGain +
                        shoulder * highlightShoulderGain * pow(facing, 1.35) +
                        core * highlightCoreGain * pow(facing, 1.50) +
                        filament * highlightFilamentGain * pow(facing, 1.70) +
                        secondaryFilament * secondaryRimGain * pow(opposite, 1.30);

                    CGFloat shadowOffset =
                        (insideDepth - shadowCenter) / MAX(0.001, shadowWidth);
                    CGFloat shadowBand =
                        exp(-(shadowOffset * shadowOffset * 1.20));
                    CGFloat dark =
                        shadowBand * shadowGain * pow(opposite, 1.20);

                    signedLight += white - dark;
                }
            }

            signedLight = MIN(0.300, MAX(-0.055, signedLight));
            CGFloat alpha = fabs(signedLight) * edgeCoverage;
            if (alpha < 0.001) continue;

            size_t index = py * bytesPerRow + px * 4;
            unsigned char a =
                (unsigned char)lround(GFClamp01(alpha) * 255.0);

            if (signedLight >= 0.0) {
                pixels[index + 0] = a;
                pixels[index + 1] = a;
                pixels[index + 2] = a;
                pixels[index + 3] = a;
            } else {
                pixels[index + 0] = 0;
                pixels[index + 1] = 0;
                pixels[index + 2] = 0;
                pixels[index + 3] = a;
            }
        }
    }

    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!cgImage) return nil;

    UIImage *image =
        [UIImage imageWithCGImage:cgImage
                            scale:renderScale
                      orientation:UIImageOrientationUp];

    if (image) {
        [cache setObject:image
                  forKey:cacheKey
                    cost:pixelWidth * pixelHeight * 4];
    }

    CGImageRelease(cgImage);
    return image;
}



@interface GFBackdropGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CALayer *gfOpticalLightingLayer;
@property (nonatomic, assign) CGSize gfLightingSize;
@property (nonatomic, assign) CGFloat gfLightingRadius;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) NSInteger gfStyle;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
- (instancetype)initWithStyle:(NSInteger)style
                     strength:(CGFloat)strength
              preferredRadius:(CGFloat)radius;
@end

@implementation GFBackdropGlassView

+ (Class)layerClass {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithStyle:(NSInteger)style
                     strength:(CGFloat)strength
              preferredRadius:(CGFloat)radius {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStyle = style;
        _gfStrength = MIN(1.0, MAX(0.0, strength));
        _gfPreferredRadius = MAX(0.0, radius);

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;

        BOOL isBackdropLayer =
            [NSStringFromClass(self.layer.class) containsString:@"Backdrop"];

        CGFloat e = sqrt(_gfStrength);

        if (_gfStrength > 0.001 && isBackdropLayer) {
            /*
             * Preserve wallpaper color instead of whitening it.
             * At 45–55%, blur stays moderate while saturation is boosted.
             */
            CGFloat blurRadius;
            CGFloat saturation;
            CGFloat brightness;

            if (_gfStyle == 1) {
                blurRadius = 1.8 + (5.0 * e);
                saturation = 1.04 + (0.20 * e);
                brightness = 0.001 + (0.004 * e);
            } else {
                blurRadius = 2.0 + (7.0 * e);
                saturation = 1.05 + (0.30 * e);
                brightness = 0.0;
            }

            id saturate = GFCreateCAFilter(@"colorSaturate");
            id brighten = GFCreateCAFilter(@"colorBrightness");
            id blur = GFCreateCAFilter(@"gaussianBlur");

            NSMutableArray *filters = [NSMutableArray array];

            if (saturate) {
                [saturate setValue:@(saturation) forKey:@"inputAmount"];
                [filters addObject:saturate];
            }

            if (brighten && brightness > 0.0001) {
                [brighten setValue:@(brightness) forKey:@"inputAmount"];
                [filters addObject:brighten];
            }

            if (blur) {
                [blur setValue:@(blurRadius) forKey:@"inputRadius"];
                [blur setValue:@YES forKey:@"inputNormalizeEdges"];
                [blur setValue:@YES forKey:@"inputHardEdges"];
                [filters addObject:blur];
            }

            if (filters.count > 0) {
                [self.layer setValue:filters forKey:@"filters"];
                [self.layer setValue:@1.0 forKey:@"scale"];
            }
        } else if (_gfStrength > 0.001) {
            /*
             * Conservative fallback for systems where CABackdropLayer cannot
             * be resolved. This is not the primary iOS 16 path.
             */
            UIBlurEffect *effect =
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];

            _gfFallbackBlurView =
                [[UIVisualEffectView alloc] initWithEffect:effect];

            _gfFallbackBlurView.userInteractionEnabled = NO;
            _gfFallbackBlurView.alpha =
                (_gfStyle == 1) ? MIN(0.70, 0.30 + 0.50 * e)
                                : 0.55 * _gfStrength;

            [self addSubview:_gfFallbackBlurView];
        }

        /*
         * Tiny neutral tint only. The wallpaper is meant to provide the color.
         */
        CGFloat tintAlpha = 0.0;

        if (_gfStrength > 0.001) {
            tintAlpha = (_gfStyle == 1)
                ? 0.0015 + (0.007 * e)
                : 0.018 * _gfStrength;
        }

        if (tintAlpha > 0.001) {
            _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
            _gfTintView.userInteractionEnabled = NO;
            _gfTintView.backgroundColor = UIColor.whiteColor;
            _gfTintView.alpha = tintAlpha;
            [self addSubview:_gfTintView];
        }

        if (_gfStyle == 1 && _gfStrength > 0.001) {
            _gfOpticalLightingLayer = [CALayer layer];
            _gfOpticalLightingLayer.contentsGravity = kCAGravityResize;
            _gfOpticalLightingLayer.magnificationFilter = kCAFilterLinear;
            _gfOpticalLightingLayer.minificationFilter = kCAFilterLinear;
            _gfOpticalLightingLayer.opaque = NO;

            [self.layer addSublayer:_gfOpticalLightingLayer];
        }
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfFallbackBlurView.frame = self.bounds;
    self.gfTintView.frame = self.bounds;

    /*
     * Resolve the folder radius before constructing the continuous edge mask.
     */
    CGFloat radius = self.gfPreferredRadius;

    if (radius <= 0.0 && self.superview) {
        radius = self.superview.layer.cornerRadius;
    }

    if (radius > 0.0) {
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (self.gfOpticalLightingLayer) {
        self.gfOpticalLightingLayer.frame = self.bounds;

        CGSize currentSize = self.bounds.size;
        CGFloat effectiveRadius = radius;

        if (effectiveRadius <= 0.0) {
            effectiveRadius =
                MIN(currentSize.width, currentSize.height) * 0.22;
        }

        BOOL sizeChanged =
            fabs(self.gfLightingSize.width - currentSize.width) > 0.50 ||
            fabs(self.gfLightingSize.height - currentSize.height) > 0.50;

        BOOL radiusChanged =
            fabs(self.gfLightingRadius - effectiveRadius) > 0.25;

        if (sizeChanged ||
            radiusChanged ||
            self.gfOpticalLightingLayer.contents == nil) {

            UIImage *lighting =
                GFCreateOpticalLightingImage(
                    currentSize,
                    effectiveRadius,
                    self.gfStrength
                );

            self.gfOpticalLightingLayer.contents =
                lighting ? (id)lighting.CGImage : nil;

            self.gfOpticalLightingLayer.contentsScale =
                lighting
                    ? lighting.scale
                    : UIScreen.mainScreen.scale;

            self.gfLightingSize = currentSize;
            self.gfLightingRadius = effectiveRadius;
        }
    }

}

@end


@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end



%group GFIconHooks

%hook SBFolderIconImageView

- (void)setBackgroundView:(UIView *)backgroundView {
    if (!GFEnabled) {
        %orig(backgroundView);
        return;
    }

    /*
     * Stable Test3.1 behavior at Clear 0%.
     */
    if (GFStyle == 0 && GFGlassStrength <= 0.001) {
        UIView *clearPlate = [[UIView alloc] initWithFrame:CGRectZero];
        clearPlate.backgroundColor = UIColor.clearColor;
        clearPlate.userInteractionEnabled = NO;
        %orig(clearPlate);
        return;
    }

    CGFloat originalRadius =
        backgroundView ? backgroundView.layer.cornerRadius : 0.0;

    GFBackdropGlassView *plate =
        [[GFBackdropGlassView alloc] initWithStyle:GFStyle
                                          strength:GFGlassStrength
                                   preferredRadius:originalRadius];

    %orig(plate);
}

%end

%end


%ctor {
    @autoreleasepool {
        GFLoadPreferences();

        if (objc_getClass("SBFolderIconImageView")) {
            %init(GFIconHooks);
        }
}
}
