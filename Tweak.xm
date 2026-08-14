#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>

/*
 * GlassFolders 0.7.0 Beta 1 — Optical Glass
 *
 * Rendering model:
 * - CABackdropLayer supplies real wallpaper color + blur/saturation.
 * - A cached CPU-generated optical map supplies glass lighting.
 * - Lighting is derived from rounded-rect signed distance + surface normals.
 * - Upper-left gets a bright core plus a wide soft shoulder.
 * - Lower-right gets a very weak dark falloff for thickness.
 *
 * The optical map is generated only for a new size/radius/5% strength step
 * and cached. It is NOT rendered every frame.
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
                                             CGFloat strength,
                                             BOOL opened) {
    if (size.width < 2.0 || size.height < 2.0) {
        return nil;
    }

    CGFloat screenScale = UIScreen.mainScreen.scale;

    /*
     * Closed folders need full Retina precision for the narrow specular
     * filament. Opened panels remain lower-resolution because their optical
     * field is intentionally broader and softer.
     */
    CGFloat renderScale = opened
        ? MIN(screenScale, 1.60)
        : MIN(screenScale, 3.0);

    size_t pixelWidth =
        (size_t)MAX(2.0, floor(size.width * renderScale + 0.5));
    size_t pixelHeight =
        (size_t)MAX(2.0, floor(size.height * renderScale + 0.5));

    NSInteger strengthStep =
        MAX(0, MIN(20, (NSInteger)lround(strength * 20.0)));

    NSString *cacheKey = [NSString stringWithFormat:
        @"%@-%zux%zu-r%.2f-s%ld",
        opened ? @"O" : @"C",
        pixelWidth,
        pixelHeight,
        cornerRadius,
        (long)strengthStep
    ];

    NSCache *cache = GFOpticalLightingCache();
    UIImage *cached = [cache objectForKey:cacheKey];

    if (cached) {
        return cached;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = pixelWidth * 4;

    CGContextRef context = CGBitmapContextCreate(
        NULL,
        pixelWidth,
        pixelHeight,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );

    CGColorSpaceRelease(colorSpace);

    if (!context) {
        return nil;
    }

    unsigned char *pixels =
        (unsigned char *)CGBitmapContextGetData(context);

    if (!pixels) {
        CGContextRelease(context);
        return nil;
    }

    CGFloat width = (CGFloat)pixelWidth;
    CGFloat height = (CGFloat)pixelHeight;
    CGFloat radius = MAX(0.0, cornerRadius * renderScale);

    CGFloat e = sqrt(GFClamp01(strength));

    /*
     * Three-zone optical edge profile.
     *
     * FILAMENT:
     *   Sub-point, relatively crisp neutral-white reflection.
     *   This is the readable highlight edge visible in the supplied UI/icon
     *   references. It must NOT be blurred away.
     *
     * CORE:
     *   Slightly wider reflection supporting the filament.
     *
     * SHOULDER:
     *   Wide, low-contrast falloff that makes the bright core blend naturally
     *   into the glass material.
     *
     * This avoids both previous failure modes:
     *   hard white stroke  <->  completely invisible blur.
     */
    CGFloat shoulderPoints = opened
        ? (11.0 + 3.8 * e)
        : (4.4 + 2.0 * e);

    CGFloat corePoints = opened
        ? (1.85 + 0.55 * e)
        : (0.95 + 0.28 * e);

    CGFloat filamentPoints = opened
        ? (0.56 + 0.12 * e)
        : (0.38 + 0.12 * e);

    CGFloat shoulderWidth = shoulderPoints * renderScale;
    CGFloat coreWidth = corePoints * renderScale;
    CGFloat filamentWidth = filamentPoints * renderScale;

    CGFloat highlightShoulderGain = opened
        ? (0.034 + 0.010 * e)
        : (0.054 + 0.016 * e);

    CGFloat highlightCoreGain = opened
        ? (0.060 + 0.014 * e)
        : (0.125 + 0.028 * e);

    CGFloat highlightFilamentGain = opened
        ? (0.032 + 0.010 * e)
        : (0.205 + 0.045 * e);

    /*
     * Faint neutral edge definition independent of light direction.
     *
     * Closed folders use this to preserve the subtle right/bottom edge seen
     * in the supplied RootHide/Alook references.
     *
     * Opened folders keep it much weaker so the large panel never develops
     * bright corner dots or a painted frame.
     */
    CGFloat baseEdgeGain = opened
        ? (0.0035 + 0.0015 * e)
        : (0.012 + 0.004 * e);

    /*
     * Back-side transmitted rim.
     *
     * On the closed folder this creates the subtle RIGHT/BOTTOM bright edge
     * visible in the user's preferred earlier build and the Alook reference.
     *
     * It uses the narrow filament profile, so it remains thin.
     * The darker shoulder below it supplies thickness without erasing it.
     */
    CGFloat backFilamentGain = opened
        ? (0.004 + 0.002 * e)
        : (0.052 + 0.014 * e);

    CGFloat shadowShoulderGain = opened
        ? (0.009 + 0.004 * e)
        : (0.020 + 0.006 * e);

    /*
     * Keep the dark CORE weak. A strong dark core was the reason Beta3 lost
     * the right/bottom highlight completely.
     */
    CGFloat shadowCoreGain = opened
        ? (0.006 + 0.003 * e)
        : (0.007 + 0.003 * e);

    /*
     * Upper-left fixed light.
     * UIKit +Y points down, hence the negative Y component.
     */
    CGFloat lightX = -0.735;
    CGFloat lightY = -0.678;

    CGFloat epsilon = MAX(0.65, renderScale * 0.55);

    for (size_t py = 0; py < pixelHeight; py++) {
        for (size_t px = 0; px < pixelWidth; px++) {
            CGFloat x = (CGFloat)px + 0.5;
            CGFloat y = (CGFloat)py + 0.5;

            CGFloat sdf =
                GFRoundedRectSDF(
                    x, y, width, height, radius
                );

            /*
             * Smooth coverage around the mathematical rounded-rect boundary.
             *
             * Beta2 used a binary inside/outside cutoff. At large opened-panel
             * corners, a few high-contrast pixels could survive as tiny white
             * corner artifacts. A sub-pixel coverage ramp removes that without
             * blurring the actual optical highlight.
             */
            CGFloat aaWidth = MAX(0.85, renderScale * 0.72);
            CGFloat edgeCoverage =
                GFClamp01(0.5 - sdf / aaWidth);

            if (edgeCoverage <= 0.001) {
                continue;
            }

            CGFloat insideDepth = MAX(0.0, -sdf);

            /*
             * Extremely weak whole-surface diagonal bias.
             * This creates a broad light-to-dark direction without a stripe.
             */
            CGFloat u = x / MAX(1.0, width);
            CGFloat v = y / MAX(1.0, height);
            CGFloat diagonal =
                GFClamp01(1.0 - (u + v) * 0.5);

            CGFloat ambientWhite =
                pow(diagonal, 2.45) *
                (opened ? 0.0065 : 0.0075);

            CGFloat ambientDark =
                pow(1.0 - diagonal, 2.60) *
                (opened ? 0.0038 : 0.0048);

            CGFloat signedLight =
                ambientWhite - ambientDark;

            CGFloat maxBand = shoulderWidth * 3.2;

            if (insideDepth <= maxBand) {
                /*
                 * Numerical gradient of the SDF = local outward normal.
                 */
                CGFloat dx =
                    GFRoundedRectSDF(
                        x + epsilon, y, width, height, radius
                    ) -
                    GFRoundedRectSDF(
                        x - epsilon, y, width, height, radius
                    );

                CGFloat dy =
                    GFRoundedRectSDF(
                        x, y + epsilon, width, height, radius
                    ) -
                    GFRoundedRectSDF(
                        x, y - epsilon, width, height, radius
                    );

                CGFloat normalLength = hypot(dx, dy);

                if (normalLength > 0.0001) {
                    CGFloat nx = dx / normalLength;
                    CGFloat ny = dy / normalLength;

                    CGFloat ndotl =
                        nx * lightX + ny * lightY;

                    CGFloat facing = MAX(0.0, ndotl);
                    CGFloat opposite = MAX(0.0, -ndotl);

                    CGFloat shoulderRatio =
                        insideDepth /
                        MAX(0.001, shoulderWidth);

                    CGFloat coreRatio =
                        insideDepth /
                        MAX(0.001, coreWidth);

                    CGFloat filamentRatio =
                        insideDepth /
                        MAX(0.001, filamentWidth);

                    /*
                     * Gaussian-like falloff for shoulder/core.
                     * Filament uses a steeper exponent so it stays visually
                     * defined instead of becoming another fuzzy band.
                     */
                    CGFloat shoulder =
                        exp(-(shoulderRatio * shoulderRatio));

                    CGFloat core =
                        exp(-(coreRatio * coreRatio * 1.25));

                    CGFloat filament =
                        exp(-pow(filamentRatio, 2.65));

                    /*
                     * The crisp filament is more directional than the broad
                     * shoulder. This concentrates it on upper-left-facing
                     * edges/corners and prevents a white outline around the
                     * entire folder.
                     */
                    CGFloat shoulderFacing =
                        pow(facing, opened ? 1.22 : 1.32);

                    CGFloat coreFacing =
                        pow(facing, opened ? 1.38 : 1.52);

                    CGFloat filamentFacing =
                        pow(facing, opened ? 1.58 : 1.78);

                    CGFloat shadowFacing =
                        pow(opposite, opened ? 1.22 : 1.34);

                    /*
                     * baseEdge is deliberately tied to the narrow filament
                     * profile. It gives the unlit right/bottom sides a thin,
                     * low-contrast glass edge while the directional light adds
                     * the stronger upper-left reflection.
                     */
                    CGFloat baseEdge =
                        filament * baseEdgeGain;

                    /*
                     * `opposite` is strongest on lower-right-facing normals.
                     * The exponent keeps this transmitted rim mostly on the
                     * actual right/bottom edge rather than the whole perimeter.
                     */
                    CGFloat backFacing =
                        pow(opposite, opened ? 1.55 : 1.20);

                    CGFloat backRim =
                        filament * backFilamentGain * backFacing;

                    CGFloat white =
                        baseEdge +
                        backRim +
                        shoulder * highlightShoulderGain * shoulderFacing +
                        core * highlightCoreGain * coreFacing +
                        filament * highlightFilamentGain * filamentFacing;

                    /*
                     * The shadow is deliberately wider than `backRim`.
                     * Visual profile on the lower-right becomes:
                     *
                     *   thin bright rim -> subtle dark inner shoulder -> glass
                     *
                     * instead of Beta3's:
                     *   dark edge -> no visible rim.
                     */
                    CGFloat dark =
                        (
                            shoulder * shadowShoulderGain +
                            core * shadowCoreGain
                        ) * shadowFacing;

                    signedLight += white - dark;
                }
            }

            /*
             * Prevent the lighting map from ever becoming a painted frame.
             */
            /*
             * Closed folders are allowed a clearer specular peak because the
             * new filament is sub-point and highly directional.
             */
            CGFloat positiveCap =
                opened ? 0.145 : 0.295;

            CGFloat negativeCap =
                opened ? 0.045 : 0.060;

            signedLight =
                MIN(
                    positiveCap,
                    MAX(-negativeCap, signedLight)
                );

            CGFloat alpha =
                fabs(signedLight) * edgeCoverage;

            if (alpha < 0.001) {
                continue;
            }

            size_t index =
                py * bytesPerRow + px * 4;

            unsigned char a =
                (unsigned char)lround(
                    GFClamp01(alpha) * 255.0
                );

            if (signedLight >= 0.0) {
                /*
                 * Premultiplied neutral white.
                 */
                pixels[index + 0] = a;
                pixels[index + 1] = a;
                pixels[index + 2] = a;
                pixels[index + 3] = a;
            } else {
                /*
                 * Premultiplied neutral black.
                 */
                pixels[index + 0] = 0;
                pixels[index + 1] = 0;
                pixels[index + 2] = 0;
                pixels[index + 3] = a;
            }
        }
    }

    CGImageRef cgImage =
        CGBitmapContextCreateImage(context);

    CGContextRelease(context);

    if (!cgImage) {
        return nil;
    }

    UIImage *image =
        [UIImage imageWithCGImage:cgImage
                            scale:renderScale
                      orientation:UIImageOrientationUp];

    size_t cost =
        pixelWidth * pixelHeight * 4;

    if (image) {
        [cache setObject:image
                  forKey:cacheKey
                    cost:cost];
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
                    self.gfStrength,
                    NO
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


/*
 * Large opened-folder glass panel.
 *
 * It deliberately has its own calibration instead of scaling the small icon
 * plate 1:1. A larger surface should read slightly "thicker", while still
 * letting wallpaper color pass through clearly.
 *
 * Still lightweight:
 * - one CABackdropLayer-backed view
 * - static CAFilter chain
 * - one faint outline
 * - one neutral-white rim gradient
 * - no animation loop / timer / motion sensor
 */
@interface GFOpenedFolderGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CALayer *gfOpticalLightingLayer;
@property (nonatomic, strong) CAShapeLayer *gfCornerMask;
@property (nonatomic, assign) CGSize gfLightingSize;
@property (nonatomic, assign) CGFloat gfLightingRadius;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
- (instancetype)initWithStrength:(CGFloat)strength;
- (void)setPreferredRadius:(CGFloat)radius;
@end

@implementation GFOpenedFolderGlassView

+ (Class)layerClass {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithStrength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStrength = MIN(1.0, MAX(0.0, strength));

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.layer.allowsEdgeAntialiasing = YES;

        /*
         * Dedicated rounded shape mask.
         * This is intentionally separate from cornerRadius/masksToBounds:
         * the mask guarantees that backdrop filters and the optical texture
         * cannot leave tiny bright pixels at the four panel corners.
         */
        _gfCornerMask = [CAShapeLayer layer];
        _gfCornerMask.fillColor = UIColor.whiteColor.CGColor;
        _gfCornerMask.contentsScale = UIScreen.mainScreen.scale;
        self.layer.mask = _gfCornerMask;

        BOOL isBackdropLayer =
            [NSStringFromClass(self.layer.class) containsString:@"Backdrop"];

        CGFloat e = sqrt(_gfStrength);

        if (_gfStrength > 0.001 && isBackdropLayer) {
            /*
             * Slightly thicker than the closed-folder plate:
             * - more blur because the surface is much larger
             * - still restrained saturation
             * - almost no brightness lift
             */
            /*
             * Opened "frosted transparent" calibration:
             * visibly softer than the closed icon, but still transparent.
             */
            CGFloat blurRadius = 3.8 + (7.2 * e);
            CGFloat saturation = 1.06 + (0.12 * e);
            CGFloat brightness = 0.026 + (0.020 * e);

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
            UIBlurEffect *effect =
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];

            _gfFallbackBlurView =
                [[UIVisualEffectView alloc] initWithEffect:effect];
            _gfFallbackBlurView.userInteractionEnabled = NO;
            _gfFallbackBlurView.alpha =
                MIN(0.66, 0.24 + (0.46 * e));

            [self addSubview:_gfFallbackBlurView];
        }

        /*
         * Keep the opened folder neutral.
         * Wallpaper remains the color source.
         */
        CGFloat tintAlpha = 0.058 + (0.032 * e);

        if (_gfStrength > 0.001 && tintAlpha > 0.001) {
            _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
            _gfTintView.userInteractionEnabled = NO;
            _gfTintView.backgroundColor = UIColor.whiteColor;
            _gfTintView.alpha = tintAlpha;
            [self addSubview:_gfTintView];
        }

        if (_gfStrength > 0.001) {
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

- (void)setPreferredRadius:(CGFloat)radius {
    self.gfPreferredRadius = MAX(0.0, radius);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfFallbackBlurView.frame = self.bounds;
    self.gfTintView.frame = self.bounds;

    CGFloat radius = self.gfPreferredRadius;

    if (radius <= 0.0 && self.superview) {
        radius = self.superview.layer.cornerRadius;
    }

    /*
     * Fallback only when SpringBoard does not expose a radius on the
     * container/background view.
     */
    if (radius <= 0.0) {
        radius = MIN(CGRectGetWidth(self.bounds),
                     CGRectGetHeight(self.bounds)) * 0.095;
    }

    if (radius > 0.0) {
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }

    if (self.gfCornerMask) {
        /*
         * Exact panel geometry.
         *
         * Do NOT inset the custom panel. Beta3's inset could reveal the stock
         * material behind it at the four corners.
         */
        UIBezierPath *maskPath =
            [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                       cornerRadius:radius];

        self.gfCornerMask.frame = self.bounds;
        self.gfCornerMask.path = maskPath.CGPath;
    }

    if (self.gfOpticalLightingLayer) {
        self.gfOpticalLightingLayer.frame = self.bounds;

        CGSize currentSize = self.bounds.size;
        CGFloat effectiveRadius = radius;

        BOOL sizeChanged =
            fabs(self.gfLightingSize.width - currentSize.width) > 0.75 ||
            fabs(self.gfLightingSize.height - currentSize.height) > 0.75;

        BOOL radiusChanged =
            fabs(self.gfLightingRadius - effectiveRadius) > 0.35;

        if (sizeChanged ||
            radiusChanged ||
            self.gfOpticalLightingLayer.contents == nil) {

            UIImage *lighting =
                GFCreateOpticalLightingImage(
                    currentSize,
                    effectiveRadius,
                    self.gfStrength,
                    YES
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


static BOOL GFViewIsDescendantOfGlass(UIView *view) {
    UIView *cursor = view;

    while (cursor) {
        if ([cursor isKindOfClass:[GFOpenedFolderGlassView class]]) {
            return YES;
        }
        cursor = cursor.superview;
    }

    return NO;
}

static CGFloat GFOpenedHostScore(UIView *view,
                                 UIView *root,
                                 NSInteger depth) {
    if (!view || view == root || GFViewIsDescendantOfGlass(view)) {
        return -CGFLOAT_MAX;
    }

    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width < 100.0 || height < 100.0) {
        return -CGFLOAT_MAX;
    }

    CGFloat rootArea =
        MAX(1.0, CGRectGetWidth(root.bounds) * CGRectGetHeight(root.bounds));
    CGFloat area = width * height;
    CGFloat ratio = area / rootArea;

    /*
     * Reject almost-fullscreen containers. That exact fallback caused the
     * 0.5.11–0.6 RC2 "whole screen is blurred" bug.
     */
    if (ratio >= 0.90 || ratio <= 0.035) {
        return -CGFLOAT_MAX;
    }

    CGFloat aspect = width / MAX(1.0, height);

    /*
     * Folder panels are broad rounded surfaces, not tall/narrow controls.
     */
    if (aspect < 0.48 || aspect > 1.85) {
        return -CGFLOAT_MAX;
    }

    NSString *name = NSStringFromClass(view.class);
    CGFloat score = 0.0;

    /*
     * Strongest signals first.
     * These names are resolved dynamically; no private header/link required.
     */
    if ([name containsString:@"FloatyFolderBackgroundClip"]) score += 1400.0;
    if ([name containsString:@"FolderBackground"]) score += 1200.0;
    if ([name containsString:@"BackgroundClip"]) score += 1000.0;
    if ([name containsString:@"Background"]) score += 600.0;
    if ([name containsString:@"Material"]) score += 420.0;
    if ([name containsString:@"Backdrop"]) score += 420.0;

    /*
     * Rounded geometry is a useful secondary signal on iOS 16 where class
     * names can differ between builds.
     */
    CGFloat radius = view.layer.cornerRadius;
    if (radius >= 12.0) score += 300.0;
    if (radius >= 24.0) score += 180.0;

    /*
     * Prefer a panel-sized surface around 18–60% of the full container.
     */
    if (ratio >= 0.18 && ratio <= 0.60) {
        score += 260.0;
    } else if (ratio >= 0.08 && ratio < 0.75) {
        score += 120.0;
    }

    /*
     * Prefer shallower descendants if scores are otherwise similar.
     */
    score -= (CGFloat)depth * 8.0;

    return score;
}

static void GFSearchOpenedFolderHostRecursive(UIView *view,
                                              UIView *root,
                                              NSInteger depth,
                                              UIView **bestView,
                                              CGFloat *bestScore) {
    if (!view || depth > 7 || GFViewIsDescendantOfGlass(view)) {
        return;
    }

    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[GFOpenedFolderGlassView class]]) {
            continue;
        }

        CGFloat score = GFOpenedHostScore(subview, root, depth);

        if (score > *bestScore) {
            *bestScore = score;
            *bestView = subview;
        }

        GFSearchOpenedFolderHostRecursive(
            subview,
            root,
            depth + 1,
            bestView,
            bestScore
        );
    }
}

static UIView *GFOpenedFolderPanelHost(UIView *root) {
    UIView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;

    GFSearchOpenedFolderHostRecursive(
        root,
        root,
        0,
        &best,
        &bestScore
    );

    /*
     * Require real evidence that this is a panel/background.
     * Never return root/self as a fallback.
     */
    if (!best || bestScore < 430.0) {
        return nil;
    }

    return best;
}


static BOOL GFLooksLikeStockOpenedMaterialView(UIView *view) {
    if (!view ||
        [view isKindOfClass:[GFOpenedFolderGlassView class]]) {
        return NO;
    }

    NSString *name = NSStringFromClass(view.class);

    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        return YES;
    }

    return
        [name containsString:@"Backdrop"] ||
        [name containsString:@"Material"] ||
        [name containsString:@"BackgroundEffect"] ||
        [name containsString:@"BackgroundView"] ||
        [name containsString:@"FolderBackground"];
}

static void GFHideStockOpenedMaterialRecursive(UIView *container,
                                               GFOpenedFolderGlassView *glass,
                                               NSInteger depth) {
    if (!container || depth > 4) {
        return;
    }

    CGFloat containerArea =
        MAX(1.0,
            CGRectGetWidth(container.bounds) *
            CGRectGetHeight(container.bounds));

    for (UIView *subview in container.subviews) {
        if (subview == glass ||
            [subview isKindOfClass:[GFOpenedFolderGlassView class]]) {
            continue;
        }

        CGFloat area =
            CGRectGetWidth(subview.bounds) *
            CGRectGetHeight(subview.bounds);

        CGFloat ratio = area / containerArea;

        /*
         * Only suppress material-like views that occupy a substantial part of
         * the resolved PANEL host. Tiny content/background views are ignored.
         */
        if (ratio >= 0.55 &&
            GFLooksLikeStockOpenedMaterialView(subview)) {
            subview.alpha = 0.0;
            continue;
        }

        GFHideStockOpenedMaterialRecursive(
            subview,
            glass,
            depth + 1
        );
    }
}

static void GFPrepareOpenedPanelHost(UIView *host,
                                     GFOpenedFolderGlassView *glass,
                                     CGFloat radius) {
    if (!host) {
        return;
    }

    /*
     * The host itself becomes the authoritative clip geometry.
     * This prevents any child material from protruding at the corners.
     */
    host.clipsToBounds = YES;
    host.layer.masksToBounds = YES;

    if (radius > 0.0) {
        host.layer.cornerRadius = radius;
        host.layer.cornerCurve = kCACornerCurveContinuous;
    }

    host.backgroundColor = UIColor.clearColor;

    GFHideStockOpenedMaterialRecursive(
        host,
        glass,
        0
    );
}



@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end

@interface SBFloatyFolderView : UIView
- (void)setBackgroundAlpha:(double)alpha;
- (void)layoutSubviews;
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


/*
 * Opened-folder glass storage:
 * use Objective-C associated objects instead of adding a property to the
 * private SpringBoard class. This keeps Clang/Logos type checking simple.
 */
static char kGFOpenedFolderGlassAssociationKey;

static inline GFOpenedFolderGlassView *GFGetOpenedGlassView(id object) {
    return (GFOpenedFolderGlassView *)objc_getAssociatedObject(
        object,
        &kGFOpenedFolderGlassAssociationKey
    );
}

static inline void GFSetOpenedGlassView(id object,
                                       GFOpenedFolderGlassView *glass) {
    objc_setAssociatedObject(
        object,
        &kGFOpenedFolderGlassAssociationKey,
        glass,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}


%group GFOpenedFolderHooks

%hook SBFloatyFolderView

- (void)layoutSubviews {
    %orig;

    GFOpenedFolderGlassView *glass = GFGetOpenedGlassView(self);

    if (!GFEnabled || GFStyle != 1) {
        if (glass) {
            [glass removeFromSuperview];
            GFSetOpenedGlassView(self, nil);
        }
        return;
    }

    UIView *host = GFOpenedFolderPanelHost(self);

    /*
     * Professional fallback policy:
     * if we cannot identify the real rounded folder panel, do NOT put a
     * custom backdrop on SBFloatyFolderView itself. Keep stock appearance.
     */
    if (!host) {
        if (glass) {
            [glass removeFromSuperview];
            GFSetOpenedGlassView(self, nil);
        }
        return;
    }

    if (!glass) {
        glass =
            [[GFOpenedFolderGlassView alloc] initWithStrength:GFGlassStrength];
        GFSetOpenedGlassView(self, glass);
    }

    if (glass.superview != host) {
        [glass removeFromSuperview];
        [host insertSubview:glass atIndex:0];
    }

    glass.frame = host.bounds;

    CGFloat targetRadius = host.layer.cornerRadius;

    /*
     * If the clip host itself carries no radius, use a restrained geometric
     * fallback based on the PANEL, not the full screen.
     */
    if (targetRadius <= 0.0) {
        targetRadius =
            MIN(CGRectGetWidth(host.bounds),
                CGRectGetHeight(host.bounds)) * 0.085;
    }

    [glass setPreferredRadius:targetRadius];

    /*
     * Clip the real host and remove any stock material still peeking behind
     * the custom glass. This specifically targets the four-corner "ears".
     */
    GFPrepareOpenedPanelHost(
        host,
        glass,
        targetRadius
    );

    [host sendSubviewToBack:glass];
}

- (void)setBackgroundAlpha:(double)alpha {
    if (!GFEnabled || GFStyle != 1) {
        %orig(alpha);
        return;
    }

    GFOpenedFolderGlassView *glass = GFGetOpenedGlassView(self);
    UIView *host = GFOpenedFolderPanelHost(self);

    /*
     * If the panel host is unresolved, preserve Apple's stock folder
     * background. This prevents the old "entire screen blurred" failure.
     */
    if (!host) {
        if (glass) {
            [glass removeFromSuperview];
            GFSetOpenedGlassView(self, nil);
        }

        %orig(alpha);
        return;
    }

    if (!glass) {
        glass =
            [[GFOpenedFolderGlassView alloc] initWithStrength:GFGlassStrength];
        GFSetOpenedGlassView(self, glass);
    }

    if (glass.superview != host) {
        [glass removeFromSuperview];
        [host insertSubview:glass atIndex:0];
    }

    glass.frame = host.bounds;

    CGFloat targetRadius = host.layer.cornerRadius;

    if (targetRadius <= 0.0) {
        targetRadius =
            MIN(CGRectGetWidth(host.bounds),
                CGRectGetHeight(host.bounds)) * 0.085;
    }

    [glass setPreferredRadius:targetRadius];

    GFPrepareOpenedPanelHost(
        host,
        glass,
        targetRadius
    );

    [host sendSubviewToBack:glass];

    /*
     * Apple's original folder transition still drives panel opacity.
     */
    glass.alpha = MIN(1.0, MAX(0.0, alpha));

    /*
     * Only now—after a valid panel host exists—hide Apple's original panel
     * material. The surrounding full-screen wallpaper blur/dim stays stock.
     */
    %orig(0.0);
}

%end

%end


%ctor {
    @autoreleasepool {
        GFLoadPreferences();

        if (objc_getClass("SBFolderIconImageView")) {
            %init(GFIconHooks);
        }

        if (objc_getClass("SBFloatyFolderView")) {
            %init(GFOpenedFolderHooks);
        }
    }
}
