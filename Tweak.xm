#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <dlfcn.h>

/*
 * GlassFolders 0.7.3 Beta 1.4 — Exact App Library Hook
 *
 * Scope:
 * - stable closed SpringBoard folder icon path
 * - opened panel is attached only to SBFolderBackgroundView
 * - optional App Library category-card background glass
 * - no parent folder container / page-background factory / transition hook
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
static BOOL GFAppLibraryPodsEnabled = NO;
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
    GFAppLibraryPodsEnabled =
        GFReadBool(CFSTR("AppLibraryPodsEnabled"), NO);
    GFStyle = GFReadInteger(CFSTR("Style"), 0);
    GFGlassStrength = GFReadPercent(CFSTR("GlassStrength"), 55.0);

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


/*
 * Glass Strength is deliberately NOT mapped through one sqrt() curve.
 *
 * Material:
 *   slightly slower than linear -> 55% remains transparent instead of
 *   already behaving like ~74%.
 *
 * Specular:
 *   slightly faster -> edge reflection is visible without requiring a
 *   heavily blurred body.
 *
 * Tint:
 *   slower still -> high strength does not turn into a milky white card.
 */
static inline CGFloat GFMaterialResponse(CGFloat strength) {
    return pow(GFClamp01(strength), 1.10);
}

static inline CGFloat GFSpecularResponse(CGFloat strength) {
    return pow(GFClamp01(strength), 0.80);
}

static inline CGFloat GFTintResponse(CGFloat strength) {
    return pow(GFClamp01(strength), 1.35);
}


/*
 * Dedicated optical-edge response.
 *
 * 25%  -> ~0.10
 * 50%  -> ~0.29
 * 55%  -> ~0.35
 * 75%  -> ~0.62
 * 100% -> 1.00
 *
 * This gives the slider visible optical authority: high percentages now
 * increase specular brightness much more clearly instead of mostly changing
 * the glass body.
 */
static inline CGFloat GFEdgeResponse(CGFloat strength) {
    CGFloat s = GFClamp01(strength);
    return 0.12 * s + 0.88 * pow(s, 1.80);
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

    /*
     * Beta5: the desktop folder now uses the SAME dedicated percentage
     * response as the opened panel. This is the important correction:
     * 75% and 100% must no longer collapse into nearly the same appearance.
     */
    CGFloat edgeDrive = GFEdgeResponse(strength);

    /* Geometry changes only a little; luminance changes strongly. */
    CGFloat shoulderWidth =
        (4.1 + 1.0 * edgeDrive) * renderScale;

    CGFloat coreWidth =
        (0.78 + 0.20 * edgeDrive) * renderScale;

    CGFloat filamentWidth =
        (0.43 + 0.10 * edgeDrive) * renderScale;

    /*
     * Directional upper-left light. Fixed terms are deliberately small;
     * percentage owns most of the brightness budget.
     */
    CGFloat highlightShoulderGain =
        0.012 + 0.050 * edgeDrive;

    CGFloat highlightCoreGain =
        0.030 + 0.180 * edgeDrive;

    CGFloat highlightFilamentGain =
        0.045 + 0.310 * edgeDrive;

    /*
     * Far-side rim remains, but vertical straight edges will be attenuated
     * below. Bottom and bottom-right are allowed to stay bright.
     */
    CGFloat secondaryRimWidth =
        (0.58 + 0.12 * edgeDrive) * renderScale;

    CGFloat secondaryRimGain =
        0.022 + 0.150 * edgeDrive;

    /*
     * Dark thickness starts inside the white edge. Its growth is restrained
     * so 100% gets brighter, not merely darker/thicker.
     */
    CGFloat shadowCenter =
        (2.15 + 0.30 * edgeDrive) * renderScale;

    CGFloat shadowWidth =
        (1.55 + 0.22 * edgeDrive) * renderScale;

    CGFloat shadowGain =
        0.006 + 0.008 * edgeDrive;

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

                    /*
                     * Surface-axis redistribution.
                     *
                     * horizontalEdge = top/bottom
                     * verticalEdge   = left/right
                     *
                     * The 100% screenshot showed that straight left/right
                     * sides were already strong while TL/BR corners were not.
                     * Therefore straight vertical sides now receive much less
                     * luminance than top/bottom and the selected corners.
                     */
                    CGFloat horizontalEdge =
                        pow(fabs(ny), 2.00);

                    CGFloat verticalEdge =
                        pow(fabs(nx), 2.00);

                    CGFloat topFacing =
                        MAX(0.0, -ny);

                    CGFloat bottomFacing =
                        MAX(0.0, ny);

                    /*
                     * Very low continuous floor: enough to preserve the shape
                     * without producing a uniform white rounded rectangle.
                     */
                    CGFloat perimeterFloor =
                        0.0035 + 0.0055 * edgeDrive;

                    CGFloat horizontalRailGain =
                        0.010 + 0.125 * edgeDrive;

                    CGFloat verticalRailGain =
                        0.003 + 0.032 * edgeDrive;

                    CGFloat topRail =
                        horizontalEdge *
                        topFacing *
                        horizontalRailGain;

                    CGFloat bottomRail =
                        horizontalEdge *
                        bottomFacing *
                        (0.008 + 0.105 * edgeDrive);

                    CGFloat sideRail =
                        verticalEdge *
                        verticalRailGain;

                    /*
                     * Top-left + bottom-right rounded-corner bridge.
                     * nx*ny > 0 selects precisely those two diagonal corners.
                     * Broad exponent keeps the highlight connected through
                     * the radius instead of forming an isolated hot pixel.
                     */
                    CGFloat pairedCorner =
                        GFClamp01(
                            2.20 * MAX(0.0, nx * ny)
                        );

                    CGFloat cornerBridge =
                        pow(pairedCorner, 0.88);

                    CGFloat cornerFilamentGain =
                        0.020 + 0.340 * edgeDrive;

                    CGFloat cornerCoreGain =
                        0.008 + 0.100 * edgeDrive;

                    /*
                     * Directional key light is attenuated on pure vertical
                     * sides, but remains strong on top and rounded corners.
                     */
                    CGFloat keyAxisWeight =
                        0.30 +
                        0.48 * horizontalEdge +
                        0.22 * cornerBridge;

                    /*
                     * The secondary far-side rim keeps bottom/bottom-right
                     * crisp while cutting the straight right edge.
                     */
                    CGFloat secondaryAxisWeight =
                        0.24 +
                        0.60 * horizontalEdge +
                        0.16 * cornerBridge;

                    CGFloat white =
                        filament * perimeterFloor +
                        filament * topRail +
                        filament * bottomRail +
                        filament * sideRail +
                        filament * cornerBridge * cornerFilamentGain +
                        core * cornerBridge * cornerCoreGain +
                        shoulder * highlightShoulderGain *
                            pow(facing, 1.35) * keyAxisWeight +
                        core * highlightCoreGain *
                            pow(facing, 1.50) * keyAxisWeight +
                        filament * highlightFilamentGain *
                            pow(facing, 1.70) * keyAxisWeight +
                        secondaryFilament * secondaryRimGain *
                            pow(opposite, 1.30) * secondaryAxisWeight;

                    CGFloat shadowOffset =
                        (insideDepth - shadowCenter) /
                        MAX(0.001, shadowWidth);

                    CGFloat shadowBand =
                        exp(-(shadowOffset * shadowOffset * 1.20));

                    CGFloat dark =
                        shadowBand *
                        shadowGain *
                        pow(opposite, 1.20) *
                        secondaryAxisWeight;

                    signedLight += white - dark;
                }
            }

            /*
             * High percentages are intentionally allowed a much brighter
             * optical peak. The clamp itself now participates in the slider
             * response instead of capping 75% and 100% at the same ceiling.
             */
            CGFloat closedEdgePeak =
                0.105 + 0.365 * edgeDrive;

            signedLight =
                MIN(
                    closedEdgePeak,
                    MAX(-0.045, signedLight)
                );
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

        CGFloat materialResponse = GFMaterialResponse(_gfStrength);
        CGFloat tintResponse = GFTintResponse(_gfStrength);

        if (_gfStrength > 0.001 && isBackdropLayer) {
            /*
             * Preserve wallpaper color instead of whitening it.
             * At 45–55%, blur stays moderate while saturation is boosted.
             */
            CGFloat blurRadius;
            CGFloat saturation;
            CGFloat brightness;

            if (_gfStyle == 1) {
                blurRadius = 1.6 + (4.2 * materialResponse);
                saturation = 1.04 + (0.16 * materialResponse);
                brightness = 0.001 + (0.003 * materialResponse);
            } else {
                blurRadius = 1.8 + (6.0 * materialResponse);
                saturation = 1.05 + (0.24 * materialResponse);
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
                (_gfStyle == 1) ? MIN(0.64, 0.24 + 0.42 * materialResponse)
                                : 0.55 * _gfStrength;

            [self addSubview:_gfFallbackBlurView];
        }

        /*
         * Tiny neutral tint only. The wallpaper is meant to provide the color.
         */
        CGFloat tintAlpha = 0.0;

        if (_gfStrength > 0.001) {
            tintAlpha = (_gfStyle == 1)
                ? 0.0010 + (0.006 * tintResponse)
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


#pragma mark - Opened folder panel: conservative material takeover

/*
 * IMPORTANT STABILITY BOUNDARY
 *
 * We deliberately do NOT hook:
 * - parent folder container hooks
 * - page-background factory hooks
 * - background-alpha transition hooks
 * - outside wallpaper-background hooks
 *
 * SBFolderBackgroundView is already the actual visual panel.  We let
 * SpringBoard create and animate it normally, then replace only its material.
 * The parent view's native alpha / transform animation therefore also drives
 * this child without a separate transition hook.
 */

static BOOL GFUsesDarkAppearance(UIView *view) {
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;

    if (view) {
        style = view.traitCollection.userInterfaceStyle;
    }

    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }

    return style == UIUserInterfaceStyleDark;
}


static UIImage *GFCreateOpenedPanelLightingImage(CGSize size,
                                                 CGFloat cornerRadius,
                                                 CGFloat strength,
                                                 BOOL darkAppearance) {
    if (size.width < 2.0 ||
        size.height < 2.0 ||
        strength <= 0.001) {
        return nil;
    }

    /*
     * The opened panel uses broader light bands than the desktop icon.
     * 1.5x is enough for the thin filament while avoiding a multi-megabyte
     * 3x render for every large folder page.
     */
    CGFloat renderScale = MIN(UIScreen.mainScreen.scale, 1.50);

    size_t pixelWidth =
        (size_t)MAX(2.0, floor(size.width * renderScale + 0.5));
    size_t pixelHeight =
        (size_t)MAX(2.0, floor(size.height * renderScale + 0.5));

    NSInteger strengthStep =
        MAX(0, MIN(20, (NSInteger)lround(strength * 20.0)));

    NSString *cacheKey = [NSString stringWithFormat:
        @"P-%@-%zux%zu-r%.2f-s%ld",
        darkAppearance ? @"D" : @"L",
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
    CGFloat e = GFSpecularResponse(strength);

    /*
     * Large surfaces should read "thicker" than the closed folder:
     * broader shoulder, but a restrained filament so it never becomes
     * a hard white rounded-rect stroke.
     */
    CGFloat shoulderWidth =
        (8.0 + 2.4 * e) * renderScale;
    CGFloat coreWidth =
        (1.30 + 0.34 * e) * renderScale;
    CGFloat filamentWidth =
        (0.62 + 0.12 * e) * renderScale;

    CGFloat shoulderGain = darkAppearance
        ? (0.030 + 0.010 * e)
        : (0.020 + 0.007 * e);

    CGFloat coreGain = darkAppearance
        ? (0.120 + 0.040 * e)
        : (0.078 + 0.028 * e);

    CGFloat filamentGain = darkAppearance
        ? (0.205 + 0.065 * e)
        : (0.135 + 0.045 * e);

    /*
     * The far edge remains visible in both appearances.
     * Light mode gets a little more dark shoulder so a pale wallpaper does
     * not erase the shape.
     */
    CGFloat secondaryRimWidth =
        (0.78 + 0.12 * e) * renderScale;

    CGFloat secondaryRimGain = darkAppearance
        ? (0.092 + 0.032 * e)
        : (0.082 + 0.030 * e);

    CGFloat darkShoulderCenter =
        (2.8 + 0.5 * e) * renderScale;

    CGFloat darkShoulderWidth =
        (2.4 + 0.5 * e) * renderScale;

    CGFloat darkShoulderGain = darkAppearance
        ? (0.008 + 0.003 * e)
        : (0.020 + 0.005 * e);

    const CGFloat invSqrt2 = 0.70710678118;
    const CGFloat lightX = -invSqrt2;
    const CGFloat lightY = -invSqrt2;

    CGFloat epsilon = MAX(0.70, renderScale * 0.60);
    CGFloat aaWidth = MAX(0.90, renderScale * 0.75);

    for (size_t py = 0; py < pixelHeight; py++) {
        for (size_t px = 0; px < pixelWidth; px++) {
            CGFloat x = (CGFloat)px + 0.5;
            CGFloat y = (CGFloat)py + 0.5;

            CGFloat sdf =
                GFRoundedRectSDF(
                    x, y, width, height, radius
                );

            CGFloat edgeCoverage =
                GFClamp01(0.5 - sdf / aaWidth);

            if (edgeCoverage <= 0.001) {
                continue;
            }

            CGFloat insideDepth = MAX(0.0, -sdf);
            CGFloat maxBand =
                MAX(
                    shoulderWidth * 3.0,
                    darkShoulderCenter + darkShoulderWidth * 3.0
                );

            if (insideDepth > maxBand) {
                continue;
            }

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

            if (normalLength <= 0.0001) {
                continue;
            }

            CGFloat nx = dx / normalLength;
            CGFloat ny = dy / normalLength;

            CGFloat ndotl = nx * lightX + ny * lightY;
            CGFloat facing = MAX(0.0, ndotl);
            CGFloat opposite = MAX(0.0, -ndotl);

            CGFloat shoulderRatio =
                insideDepth / MAX(0.001, shoulderWidth);

            CGFloat coreRatio =
                insideDepth / MAX(0.001, coreWidth);

            CGFloat filamentRatio =
                insideDepth / MAX(0.001, filamentWidth);

            CGFloat secondaryRatio =
                insideDepth / MAX(0.001, secondaryRimWidth);

            CGFloat shoulder =
                exp(-(shoulderRatio * shoulderRatio));

            CGFloat core =
                exp(-(coreRatio * coreRatio * 1.30));

            CGFloat filament =
                exp(-pow(filamentRatio, 2.55));

            CGFloat secondary =
                exp(-pow(secondaryRatio, 2.30));

            /*
             * Connected edge rail model
             *
             * 1. perimeterGain:
             *    a very fine continuous reflection so no side disappears.
             *
             * 2. horizontalRail:
             *    top and bottom receive a stronger clean highlight, matching
             *    the reference where the glass reads brighter along both
             *    horizontal edges.
             *
             * 3. cornerBridge:
             *    specifically reinforces the top-left and bottom-right
             *    rounded corners. The highlight therefore bends around the
             *    radius and connects naturally into the top/bottom rails
             *    instead of ending abruptly at the straight edge.
             *
             * Directional key light is still strongest at upper-left.
             */
            /*
             * Beta4 separates "glass exists" from "glass is strongly lit".
             * edgeDrive is the user-visible brightness control for the edge
             * optics; unlike the old constant-heavy gains, 75% and 100% now
             * look materially brighter than 55%.
             */
            CGFloat edgeDrive =
                GFEdgeResponse(strength);

            /*
             * Surface-axis weights:
             * horizontalEdge -> top/bottom
             * verticalEdge   -> left/right
             *
             * The Apple reference spends much more luminance budget on the
             * horizontal rails and the diagonal rounded corners. Straight
             * left/right sides remain present, but intentionally quieter.
             */
            CGFloat horizontalEdge =
                pow(fabs(ny), 2.10);

            CGFloat verticalEdge =
                pow(fabs(nx), 2.10);

            CGFloat topFacing =
                MAX(0.0, -ny);

            CGFloat bottomFacing =
                MAX(0.0, ny);

            /*
             * Very weak always-on perimeter floor, then strength-dependent
             * horizontal/vertical gains. Straight side gain is ~40% of the
             * horizontal baseline, which fixes the Beta3 "left/right too
             * bright" result.
             */
            CGFloat perimeterFloor = darkAppearance
                ? 0.0060
                : 0.0045;

            CGFloat horizontalPerimeterGain = darkAppearance
                ? (0.018 + 0.034 * edgeDrive)
                : (0.013 + 0.026 * edgeDrive);

            CGFloat verticalPerimeterGain = darkAppearance
                ? (0.007 + 0.014 * edgeDrive)
                : (0.006 + 0.011 * edgeDrive);

            CGFloat axisPerimeter =
                horizontalEdge * horizontalPerimeterGain +
                verticalEdge * verticalPerimeterGain;

            /*
             * Top/bottom rails scale aggressively with edgeDrive.
             * At 75% the rails are already clearly bright; at 100% they
             * approach the crisp system reference without turning the whole
             * perimeter into a uniform white stroke.
             */
            CGFloat topRailGain = darkAppearance
                ? (0.022 + 0.160 * edgeDrive)
                : (0.016 + 0.108 * edgeDrive);

            CGFloat bottomRailGain = darkAppearance
                ? (0.018 + 0.125 * edgeDrive)
                : (0.014 + 0.090 * edgeDrive);

            CGFloat horizontalRail =
                horizontalEdge *
                (
                    topFacing * topRailGain +
                    bottomFacing * bottomRailGain
                );

            /*
             * nx*ny > 0 selects the top-left and bottom-right rounded corners.
             * The response is made slightly broader than Beta3 so the light
             * visibly CONNECTS around the radius instead of appearing as an
             * isolated hot pixel near 45 degrees.
             */
            CGFloat pairedCorner =
                GFClamp01(
                    2.15 * MAX(0.0, nx * ny)
                );

            CGFloat cornerBridge =
                pow(pairedCorner, 0.92);

            /*
             * Corners receive the strongest percentage-dependent gain.
             * This is the main answer to the 75% screenshot: TL/BR now scale
             * much harder than the straight left/right sides.
             */
            CGFloat cornerBridgeGain = darkAppearance
                ? (0.025 + 0.245 * edgeDrive)
                : (0.018 + 0.165 * edgeDrive);

            CGFloat horizontalCoreGain = darkAppearance
                ? (0.008 + 0.032 * edgeDrive)
                : (0.006 + 0.023 * edgeDrive);

            CGFloat cornerCoreGain = darkAppearance
                ? (0.010 + 0.060 * edgeDrive)
                : (0.007 + 0.040 * edgeDrive);

            /*
             * The far-side secondary rim was one contributor to Beta3's
             * strong right straight edge. Keep the lower/bottom response but
             * attenuate it on vertical straight sides.
             */
            CGFloat secondaryAxisWeight =
                0.42 + 0.58 * horizontalEdge;

            CGFloat white =
                filament * perimeterFloor +
                filament * axisPerimeter +
                filament * horizontalRail +
                core * horizontalEdge * horizontalCoreGain +
                filament * cornerBridge * cornerBridgeGain +
                core * cornerBridge * cornerCoreGain +
                shoulder * shoulderGain * pow(facing, 1.30) * (0.70 + 0.30 * edgeDrive) +
                core * coreGain * pow(facing, 1.45) * (0.62 + 0.58 * edgeDrive) +
                filament * filamentGain * pow(facing, 1.65) * (0.58 + 0.72 * edgeDrive) +
                secondary * secondaryRimGain * pow(opposite, 1.25) *
                    secondaryAxisWeight *
                    (0.52 + 0.62 * edgeDrive);

            /*
             * Far-side thickness starts inside the edge.  It never occupies
             * the same pixels as the secondary white filament.
             */
            CGFloat shadowOffset =
                (insideDepth - darkShoulderCenter) /
                MAX(0.001, darkShoulderWidth);

            CGFloat dark =
                exp(-(shadowOffset * shadowOffset * 1.10)) *
                darkShoulderGain *
                pow(opposite, 1.15);

            CGFloat edgePeak =
                darkAppearance
                    ? (0.190 + 0.245 * edgeDrive)
                    : (0.145 + 0.175 * edgeDrive);

            CGFloat signedLight =
                MIN(edgePeak, MAX(-0.045, white - dark));

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

    if (image) {
        [cache setObject:image
                  forKey:cacheKey
                    cost:pixelWidth * pixelHeight * 4];
    }

    CGImageRelease(cgImage);
    return image;
}


@interface GFPanelGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CALayer *gfOpticalLayer;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) CGSize gfLightingSize;
@property (nonatomic, assign) CGFloat gfLightingRadius;
@property (nonatomic, assign) BOOL gfLastDarkAppearance;
@property (nonatomic, assign) BOOL gfHasAppearance;
- (instancetype)initWithStrength:(CGFloat)strength;
- (void)setPreferredRadius:(CGFloat)radius;
- (void)gfRefreshMaterial;
@end


@implementation GFPanelGlassView

+ (Class)layerClass {
    Class backdropClass =
        NSClassFromString(@"CABackdropLayer");

    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithStrength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStrength =
            MIN(1.0, MAX(0.0, strength));

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.layer.allowsEdgeAntialiasing = YES;

        _gfTintView =
            [[UIView alloc] initWithFrame:CGRectZero];

        _gfTintView.userInteractionEnabled = NO;
        _gfTintView.backgroundColor =
            UIColor.whiteColor;

        [self addSubview:_gfTintView];

        _gfOpticalLayer =
            [CALayer layer];

        _gfOpticalLayer.contentsGravity =
            kCAGravityResize;

        _gfOpticalLayer.magnificationFilter =
            kCAFilterLinear;

        _gfOpticalLayer.minificationFilter =
            kCAFilterLinear;

        _gfOpticalLayer.opaque = NO;

        [self.layer addSublayer:_gfOpticalLayer];

        [self gfRefreshMaterial];
    }

    return self;
}

- (void)setPreferredRadius:(CGFloat)radius {
    CGFloat safeRadius = MAX(0.0, radius);

    if (fabs(self.gfPreferredRadius - safeRadius) > 0.25) {
        self.gfPreferredRadius = safeRadius;
        [self setNeedsLayout];
    }
}

- (void)gfRefreshMaterial {
    BOOL darkAppearance =
        GFUsesDarkAppearance(self);

    self.gfLastDarkAppearance =
        darkAppearance;

    self.gfHasAppearance = YES;

    CGFloat materialResponse =
        GFMaterialResponse(self.gfStrength);

    CGFloat tintResponse =
        GFTintResponse(self.gfStrength);

    BOOL isBackdropLayer =
        [NSStringFromClass(self.layer.class)
            containsString:@"Backdrop"];

    if (self.gfStrength > 0.001 &&
        isBackdropLayer) {

        /*
         * Dark mode:
         *   a slightly stronger lift is required because SpringBoard's outer
         *   folder environment is already dimmed.
         *
         * Light mode:
         *   less white tint + less brightness so the panel does not become
         *   an opaque milky card on a bright wallpaper.
         */
        CGFloat blurRadius = darkAppearance
            ? (5.6 + 5.2 * materialResponse)
            : (5.0 + 4.4 * materialResponse);

        CGFloat saturation = darkAppearance
            ? (1.04 + 0.11 * materialResponse)
            : (1.03 + 0.07 * materialResponse);

        CGFloat brightness = darkAppearance
            ? (0.010 + 0.018 * materialResponse)
            : (0.000 + 0.004 * materialResponse);

        id saturate =
            GFCreateCAFilter(@"colorSaturate");

        id brighten =
            GFCreateCAFilter(@"colorBrightness");

        id blur =
            GFCreateCAFilter(@"gaussianBlur");

        NSMutableArray *filters =
            [NSMutableArray array];

        if (saturate) {
            [saturate
                setValue:@(saturation)
                  forKey:@"inputAmount"];

            [filters addObject:saturate];
        }

        if (brighten) {
            [brighten
                setValue:@(brightness)
                  forKey:@"inputAmount"];

            [filters addObject:brighten];
        }

        if (blur) {
            [blur
                setValue:@(blurRadius)
                  forKey:@"inputRadius"];

            [blur
                setValue:@YES
                  forKey:@"inputNormalizeEdges"];

            [blur
                setValue:@YES
                  forKey:@"inputHardEdges"];

            [filters addObject:blur];
        }

        [self.layer
            setValue:filters
              forKey:@"filters"];

        [self.layer
            setValue:@1.0
              forKey:@"scale"];

        if (self.gfFallbackBlurView) {
            [self.gfFallbackBlurView
                removeFromSuperview];

            self.gfFallbackBlurView = nil;
        }
    } else if (self.gfStrength > 0.001) {
        if (!self.gfFallbackBlurView) {
            UIBlurEffect *effect =
                [UIBlurEffect
                    effectWithStyle:
                        UIBlurEffectStyleSystemUltraThinMaterial];

            self.gfFallbackBlurView =
                [[UIVisualEffectView alloc]
                    initWithEffect:effect];

            self.gfFallbackBlurView.userInteractionEnabled =
                NO;

            [self insertSubview:self.gfFallbackBlurView
                   belowSubview:self.gfTintView];
        }

        self.gfFallbackBlurView.alpha =
            darkAppearance
                ? MIN(0.56, 0.20 + 0.34 * materialResponse)
                : MIN(0.46, 0.15 + 0.28 * materialResponse);
    }

    /*
     * Neutral tint only. Wallpaper remains the chromatic source.
     */
    self.gfTintView.alpha =
        self.gfStrength > 0.001
            ? (
                darkAppearance
                    ? (0.012 + 0.028 * tintResponse)
                    : (0.004 + 0.012 * tintResponse)
              )
            : 0.0;

    /*
     * Force the optical texture to be regenerated when light/dark mode
     * changes even if the panel dimensions are unchanged.
     */
    self.gfOpticalLayer.contents = nil;

    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    [super
        traitCollectionDidChange:
            previousTraitCollection];

    UIUserInterfaceStyle previousStyle =
        previousTraitCollection
            ? previousTraitCollection.userInterfaceStyle
            : UIUserInterfaceStyleUnspecified;

    UIUserInterfaceStyle currentStyle =
        self.traitCollection.userInterfaceStyle;

    if (previousStyle != currentStyle) {
        [self gfRefreshMaterial];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfFallbackBlurView.frame =
        self.bounds;

    self.gfTintView.frame =
        self.bounds;

    CGFloat radius =
        self.gfPreferredRadius;

    /*
     * SBFolderBackgroundView normally already has the actual system radius.
     * 38 pt is used only if the host has not exposed one yet.
     */
    if (radius <= 0.0) {
        radius = 38.0;
    }

    CGFloat maxRadius =
        MIN(
            CGRectGetWidth(self.bounds),
            CGRectGetHeight(self.bounds)
        ) * 0.50;

    radius =
        MIN(radius, maxRadius);

    self.layer.cornerRadius = radius;
    self.layer.cornerCurve =
        kCACornerCurveContinuous;

    self.gfOpticalLayer.frame =
        self.bounds;

    BOOL darkAppearance =
        GFUsesDarkAppearance(self);

    BOOL appearanceChanged =
        !self.gfHasAppearance ||
        self.gfLastDarkAppearance != darkAppearance;

    if (appearanceChanged) {
        [self gfRefreshMaterial];
        return;
    }

    CGSize currentSize =
        self.bounds.size;

    BOOL sizeChanged =
        fabs(
            self.gfLightingSize.width -
            currentSize.width
        ) > 0.75 ||
        fabs(
            self.gfLightingSize.height -
            currentSize.height
        ) > 0.75;

    BOOL radiusChanged =
        fabs(
            self.gfLightingRadius -
            radius
        ) > 0.35;

    if (self.gfOpticalLayer.contents == nil ||
        sizeChanged ||
        radiusChanged) {

        UIImage *lighting =
            GFCreateOpenedPanelLightingImage(
                currentSize,
                radius,
                self.gfStrength,
                darkAppearance
            );

        self.gfOpticalLayer.contents =
            lighting
                ? (id)lighting.CGImage
                : nil;

        self.gfOpticalLayer.contentsScale =
            lighting
                ? lighting.scale
                : UIScreen.mainScreen.scale;

        self.gfLightingSize =
            currentSize;

        self.gfLightingRadius =
            radius;
    }
}

@end


/*
 * Per-instance storage. No global array and no polling.
 */
static char kGFPanelGlassAssociationKey;
static char kGFStockSubviewWasHiddenKey;
static char kGFStockSubviewOriginalHiddenKey;


static inline BOOL GFShouldUseOpenedPanel(void) {
    return GFEnabled && GFStyle == 1;
}


static inline BOOL GFShouldUseAppLibraryPods(void) {
    /*
     * Independent App Library control:
     * master enable + this switch are sufficient.
     *
     * It still reuses the current Glass Strength and adaptive material,
     * but no longer silently depends on the desktop Style selector.
     */
    return
        GFEnabled &&
        GFAppLibraryPodsEnabled;
}


static GFPanelGlassView *GFPanelGlassForBackground(
    UIView *backgroundView
) {
    return (GFPanelGlassView *)
        objc_getAssociatedObject(
            backgroundView,
            &kGFPanelGlassAssociationKey
        );
}


static void GFSetPanelGlassForBackground(
    UIView *backgroundView,
    GFPanelGlassView *glass
) {
    objc_setAssociatedObject(
        backgroundView,
        &kGFPanelGlassAssociationKey,
        glass,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}


/*
 * Preserve the stock material objects and their lifecycle; only visibility
 * is suppressed. This is intentionally safer than deleting or recursively
 * rewriting SpringBoard's private view tree.
 */
static void GFSetStockPanelSubviewSuppressed(
    UIView *subview,
    BOOL suppressed
) {
    if (!subview ||
        [subview isKindOfClass:
            [GFPanelGlassView class]]) {
        return;
    }

    NSNumber *wasHiddenMarker =
        objc_getAssociatedObject(
            subview,
            &kGFStockSubviewWasHiddenKey
        );

    if (suppressed) {
        if (!wasHiddenMarker) {
            objc_setAssociatedObject(
                subview,
                &kGFStockSubviewOriginalHiddenKey,
                @(subview.hidden),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );

            objc_setAssociatedObject(
                subview,
                &kGFStockSubviewWasHiddenKey,
                @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        subview.hidden = YES;
    } else if (wasHiddenMarker) {
        NSNumber *originalHidden =
            objc_getAssociatedObject(
                subview,
                &kGFStockSubviewOriginalHiddenKey
            );

        subview.hidden =
            originalHidden
                ? originalHidden.boolValue
                : NO;

        objc_setAssociatedObject(
            subview,
            &kGFStockSubviewWasHiddenKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        objc_setAssociatedObject(
            subview,
            &kGFStockSubviewOriginalHiddenKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}


static void GFUpdateOpenedFolderBackground(
    UIView *backgroundView
) {
    if (!backgroundView) {
        return;
    }

    GFPanelGlassView *glass =
        GFPanelGlassForBackground(
            backgroundView
        );

    if (!GFShouldUseOpenedPanel()) {
        if (glass) {
            [glass removeFromSuperview];

            GFSetPanelGlassForBackground(
                backgroundView,
                nil
            );
        }

        for (UIView *subview
             in backgroundView.subviews) {
            GFSetStockPanelSubviewSuppressed(
                subview,
                NO
            );
        }

        return;
    }

    /*
     * The host itself can carry a stock dark fill even when all material
     * subviews are hidden.
     */
    backgroundView.backgroundColor =
        UIColor.clearColor;

    for (UIView *subview
         in backgroundView.subviews) {

        if (subview != glass) {
            GFSetStockPanelSubviewSuppressed(
                subview,
                YES
            );
        }
    }

    if (!glass) {
        glass =
            [[GFPanelGlassView alloc]
                initWithStrength:
                    GFGlassStrength];

        /*
         * Associate BEFORE insertion. If UIKit calls didAddSubview: during
         * addSubview:, the hook can already identify this as our glass.
         */
        GFSetPanelGlassForBackground(
            backgroundView,
            glass
        );

        [backgroundView
            addSubview:glass];
    } else if (glass.superview != backgroundView) {
        [glass removeFromSuperview];
        [backgroundView addSubview:glass];
    }

    glass.frame =
        backgroundView.bounds;

    glass.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    CGFloat radius =
        backgroundView.layer.cornerRadius;

    if (radius <= 0.0) {
        radius = 38.0;
    }

    [glass
        setPreferredRadius:
            radius];

    /*
     * SBFolderBackgroundView is a visual background surface; keep our layer
     * above its hidden material children. The folder icon grid is not a child
     * of this visual background class.
     */
    [backgroundView
        bringSubviewToFront:glass];
}



#pragma mark - App Library category pod glass

/*
 * App Library safety boundary
 *
 * The category card has a dedicated visual background view class. We attach
 * only to that background surface. No App Library controller, category-folder
 * controller, icon-list view, or icon view is hooked.
 *
 * This matters because the new option should be visual-only and should not
 * participate in App Library navigation, selection, layout, or folder opening.
 */
static void GFUpdateAppLibraryCategoryBackground(
    UIView *backgroundView
) {
    if (!backgroundView) {
        return;
    }

    GFPanelGlassView *glass =
        GFPanelGlassForBackground(
            backgroundView
        );

    if (!GFShouldUseAppLibraryPods()) {
        if (glass) {
            [glass removeFromSuperview];

            GFSetPanelGlassForBackground(
                backgroundView,
                nil
            );
        }

        for (UIView *subview
             in backgroundView.subviews) {

            GFSetStockPanelSubviewSuppressed(
                subview,
                NO
            );
        }

        return;
    }

    /*
     * Preserve the system background hierarchy and lifecycle; suppress only
     * its visual children while the custom glass is active.
     */
    backgroundView.backgroundColor =
        UIColor.clearColor;

    for (UIView *subview
         in backgroundView.subviews) {

        if (subview != glass) {
            GFSetStockPanelSubviewSuppressed(
                subview,
                YES
            );
        }
    }

    if (!glass) {
        glass =
            [[GFPanelGlassView alloc]
                initWithStrength:
                    GFGlassStrength];

        GFSetPanelGlassForBackground(
            backgroundView,
            glass
        );

        [backgroundView
            addSubview:glass];
    } else if (glass.superview != backgroundView) {
        [glass removeFromSuperview];

        [backgroundView
            addSubview:glass];
    }

    glass.frame =
        backgroundView.bounds;

    glass.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    /*
     * Prefer Apple's actual category-card radius. If it has not propagated to
     * the host layer yet, derive a conservative continuous radius from size.
     */
    CGFloat radius =
        backgroundView.layer.cornerRadius;

    if (radius <= 0.0) {
        CGFloat shortSide =
            MIN(
                CGRectGetWidth(backgroundView.bounds),
                CGRectGetHeight(backgroundView.bounds)
            );

        radius =
            MIN(
                34.0,
                MAX(20.0, shortSide * 0.14)
            );
    }

    [glass
        setPreferredRadius:
            radius];

    [backgroundView
        bringSubviewToFront:glass];
}


@interface SBFolderBackgroundView : UIView
@end


%group GFOpenedPanelHooks

%hook SBFolderBackgroundView

- (void)didAddSubview:(UIView *)subview {
    %orig(subview);

    if (GFShouldUseOpenedPanel() &&
        ![subview isKindOfClass:
            [GFPanelGlassView class]]) {

        /*
         * Synchronous suppression means newly-created stock material cannot
         * become the first rendered dark frame.
         */
        GFSetStockPanelSubviewSuppressed(
            subview,
            YES
        );
    }
}

- (void)didMoveToWindow {
    %orig;

    /*
     * This is after SpringBoard constructed the background object and its
     * material children, but before normal on-screen compositing.
     * We do not insert our view during the private object's initializer.
     */
    GFUpdateOpenedFolderBackground(self);
}

- (void)layoutSubviews {
    %orig;

    GFUpdateOpenedFolderBackground(self);
}

- (void)setBackgroundColor:(UIColor *)color {
    if (GFShouldUseOpenedPanel()) {
        %orig(UIColor.clearColor);
    } else {
        %orig(color);
    }
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    %orig(previousTraitCollection);

    GFPanelGlassView *glass =
        GFPanelGlassForBackground(self);

    if (glass) {
        [glass gfRefreshMaterial];
    }

    GFUpdateOpenedFolderBackground(self);
}

%end

%end






#pragma mark - App Library category-card background

@interface SBHLibraryCategoryPodBackgroundView : UIView
- (void)_updateVisualStyle;
@end


%group GFAppLibraryHooks

%hook SBHLibraryCategoryPodBackgroundView

- (void)_updateVisualStyle {
    if (GFShouldUseAppLibraryPods()) {
        /*
         * This method is the category-background style writer.
         * While custom glass is enabled, do not let it repaint the stock
         * opaque/material background over our glass.
         */
        GFUpdateAppLibraryCategoryBackground(
            self
        );

        return;
    }

    %orig;

    GFUpdateAppLibraryCategoryBackground(
        self
    );
}

- (void)didMoveToWindow {
    %orig;

    GFUpdateAppLibraryCategoryBackground(
        self
    );
}

- (void)layoutSubviews {
    %orig;

    GFUpdateAppLibraryCategoryBackground(
        self
    );
}

- (void)setBackgroundColor:(UIColor *)color {
    if (GFShouldUseAppLibraryPods()) {
        %orig(UIColor.clearColor);
    } else {
        %orig(color);
    }
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    %orig(previousTraitCollection);

    GFPanelGlassView *glass =
        GFPanelGlassForBackground(self);

    if (glass) {
        [glass gfRefreshMaterial];
    }

    GFUpdateAppLibraryCategoryBackground(
        self
    );
}

%end

%end


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

        /*
         * Opened panel is optional at runtime. If the class name changes on
         * an unexpected build, the stable desktop-folder path still loads.
         */
        if (objc_getClass("SBFolderBackgroundView")) {
            %init(GFOpenedPanelHooks);
        }

        /*
         * Deterministic App Library setup.
         *
         * The previous builds checked/guessed the class too early. Explicitly
         * load SpringBoardHome first, then initialize Logos against the exact
         * category background class used by the App Library.
         */
        dlopen(
            "/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome",
            RTLD_LAZY | RTLD_LOCAL
        );

        Class appLibraryBackgroundClass =
            objc_getClass(
                "SBHLibraryCategoryPodBackgroundView"
            );

        if (!appLibraryBackgroundClass) {
            appLibraryBackgroundClass =
                objc_getClass(
                    "_SBHLibraryCategoryPodBackgroundView"
                );
        }

        if (appLibraryBackgroundClass) {
            %init(
                GFAppLibraryHooks,
                SBHLibraryCategoryPodBackgroundView =
                    appLibraryBackgroundClass
            );
        }
    }
}
