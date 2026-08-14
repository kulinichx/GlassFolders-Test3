#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>

/*
 * GlassFolders 0.7.0 Beta 5 — Alook Optical Rim + First-Frame Open Glass
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
     * Alook-style optical perimeter model.
     *
     * Important distinction:
     *
     *   upper-left = reflected specular
     *   right/bottom = transmitted / secondary rim
     *
     * The latter must remain visible even though those normals face away from
     * the fixed upper-left light. Beta4 derived the lower-right rim only from
     * `opposite`, then immediately subtracted a broad dark shoulder; on-device
     * the result was effectively negative and the right/bottom edge vanished.
     *
     * Beta5 therefore gives the right/bottom edge its own narrow profile.
     */
    CGFloat baseEdgeGain = opened
        ? (0.0025 + 0.0010 * e)
        : (0.010 + 0.003 * e);

    /*
     * Legacy opposite-light contribution is retained at low strength because
     * it helps the rounded lower-right corner feel continuous.
     */
    CGFloat backFilamentGain = opened
        ? (0.0025 + 0.0010 * e)
        : (0.015 + 0.005 * e);

    /*
     * Explicit secondary rim width/gain.
     *
     * Closed folders intentionally expose this at roughly one third of the
     * upper-left highlight intensity: visible, but never a painted frame.
     */
    CGFloat secondaryRimPoints = opened
        ? (0.62 + 0.10 * e)
        : (0.72 + 0.18 * e);

    CGFloat secondaryRimWidth =
        secondaryRimPoints * renderScale;

    CGFloat secondaryRimGain = opened
        ? (0.0045 + 0.0015 * e)
        : (0.070 + 0.022 * e);

    /*
     * The lower-right dark shoulder starts *inside* the secondary bright rim.
     * This separation is what produces the reference profile:
     *
     *   thin clear rim -> gentle darker shoulder -> glass body
     *
     * instead of cancelling the rim at the actual edge.
     */
    CGFloat shadowStartPoints = opened
        ? (2.10 + 0.30 * e)
        : (1.20 + 0.25 * e);

    CGFloat shadowStartWidth =
        shadowStartPoints * renderScale;

    CGFloat shadowShoulderGain = opened
        ? (0.008 + 0.003 * e)
        : (0.013 + 0.004 * e);

    CGFloat shadowCoreGain = opened
        ? (0.004 + 0.002 * e)
        : (0.004 + 0.002 * e);

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
                     * Very faint neutral perimeter definition.
                     */
                    CGFloat baseEdge =
                        filament * baseEdgeGain;

                    /*
                     * Legacy back-facing term keeps the rounded lower-right
                     * corner connected to the straight right/bottom segments.
                     */
                    CGFloat backFacing =
                        pow(opposite, opened ? 1.55 : 1.20);

                    CGFloat backRim =
                        filament * backFilamentGain * backFacing;

                    /*
                     * Explicit Alook-style right/bottom secondary rim.
                     *
                     * UIKit normals:
                     *   +X = right edge
                     *   +Y = bottom edge
                     *
                     * `sideFacing` is independent of N·L, therefore those two
                     * edges do not disappear merely because the main light is
                     * upper-left. The profile is narrow and neutral white.
                     */
                    CGFloat rightFacing = MAX(0.0, nx);
                    CGFloat bottomFacing = MAX(0.0, ny);

                    CGFloat sideFacing =
                        GFClamp01(
                            hypot(rightFacing, bottomFacing)
                        );

                    CGFloat secondaryRatio =
                        insideDepth /
                        MAX(0.001, secondaryRimWidth);

                    CGFloat secondaryProfile =
                        exp(-pow(secondaryRatio, 2.10));

                    CGFloat secondaryRim =
                        secondaryProfile *
                        secondaryRimGain *
                        pow(sideFacing, opened ? 1.55 : 1.18);

                    CGFloat white =
                        baseEdge +
                        backRim +
                        secondaryRim +
                        shoulder * highlightShoulderGain * shoulderFacing +
                        core * highlightCoreGain * coreFacing +
                        filament * highlightFilamentGain * filamentFacing;

                    /*
                     * Protect the actual bright edge from the darker interior
                     * shoulder. Darkness ramps in only after the narrow rim,
                     * so it adds optical thickness without cancelling it.
                     */
                    CGFloat shadowRamp =
                        1.0 -
                        exp(
                            -pow(
                                insideDepth /
                                MAX(0.001, shadowStartWidth),
                                2.0
                            )
                        );

                    CGFloat dark =
                        (
                            shoulder * shadowShoulderGain +
                            core * shadowCoreGain
                        ) *
                        shadowFacing *
                        shadowRamp;

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



/*
 * Opened-folder architecture — Beta5
 *
 * The iOS 15.x SpringBoardHome header exposes:
 *
 *   -[SBFloatyFolderView _newPageBackgroundView]
 *   -[SBFloatyFolderView setBackgroundAlpha:]
 *   -[SBFloatyFolderView cornerRadius]
 *
 * The old Beta4 path waited for layout, recursively guessed a host view, then
 * overlaid our material. On-device that produced a visible sequence:
 *
 *   stock dark folder -> custom light glass
 *
 * Beta5 instead configures each *real page background* immediately when
 * SpringBoard creates it. We keep Apple's returned object (and therefore all
 * private contracts), suppress only its stock material content, and add our
 * glass inside it before the page is displayed.
 */

static char kGFOpenedPageGlassAssociationKey;
static char kGFOpenedPageSetAssociationKey;

static inline GFOpenedFolderGlassView *GFGetPageGlass(UIView *pageView) {
    if (!pageView) return nil;

    return (GFOpenedFolderGlassView *)objc_getAssociatedObject(
        pageView,
        &kGFOpenedPageGlassAssociationKey
    );
}

static inline void GFSetPageGlass(UIView *pageView,
                                  GFOpenedFolderGlassView *glass) {
    if (!pageView) return;

    objc_setAssociatedObject(
        pageView,
        &kGFOpenedPageGlassAssociationKey,
        glass,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static NSHashTable *GFOpenedPageSet(id floatyView, BOOL create) {
    if (!floatyView) return nil;

    NSHashTable *table =
        (NSHashTable *)objc_getAssociatedObject(
            floatyView,
            &kGFOpenedPageSetAssociationKey
        );

    if (!table && create) {
        table = [NSHashTable weakObjectsHashTable];

        objc_setAssociatedObject(
            floatyView,
            &kGFOpenedPageSetAssociationKey,
            table,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    return table;
}

static UIView *GFInvokeUIViewGetter(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);

    if (![object respondsToSelector:selector]) {
        return nil;
    }

    IMP imp = [object methodForSelector:selector];

    if (!imp) {
        return nil;
    }

    typedef id (*GFObjectGetterIMP)(id, SEL);
    GFObjectGetterIMP getter = (GFObjectGetterIMP)imp;
    id result = getter(object, selector);

    return [result isKindOfClass:[UIView class]]
        ? (UIView *)result
        : nil;
}

/*
 * SBFloatyFolderBackgroundClipView historically exposes `backgroundView`.
 * Resolve it dynamically so this source does not link a private class/header.
 */
static UIView *GFStockBackgroundForPageView(UIView *pageView) {
    if (!pageView) return nil;

    UIView *stock =
        GFInvokeUIViewGetter(pageView, @"backgroundView");

    if (stock && stock != pageView) {
        return stock;
    }

    return nil;
}

static BOOL GFLooksLikeOpenedMaterialSubview(UIView *view) {
    if (!view ||
        [view isKindOfClass:[GFOpenedFolderGlassView class]]) {
        return NO;
    }

    NSString *name = NSStringFromClass(view.class);

    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        return YES;
    }

    /*
     * SBFolderBackgroundView historically stores a full-size UIImageView tint
     * plus a UIVisualEffectView blur. A large UIImageView inside a page
     * background is therefore material, not an app icon.
     */
    if ([view isKindOfClass:[UIImageView class]]) {
        return YES;
    }

    return
        [name containsString:@"Backdrop"] ||
        [name containsString:@"Material"] ||
        [name containsString:@"Blur"] ||
        [name containsString:@"Tint"] ||
        [name containsString:@"BackgroundEffect"] ||
        [name containsString:@"FolderBackground"];
}

static void GFSuppressOpenedMaterialRecursive(UIView *container,
                                              GFOpenedFolderGlassView *glass,
                                              NSInteger depth) {
    if (!container || depth > 4) {
        return;
    }

    CGFloat containerArea =
        MAX(
            1.0,
            CGRectGetWidth(container.bounds) *
            CGRectGetHeight(container.bounds)
        );

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
         * This helper only runs inside a dedicated page-background object.
         * Suppress full-size material layers, never small decorative/content
         * views. The 0.42 threshold covers iOS variants whose blur/tint view is
         * inset slightly inside the page clip.
         */
        if (ratio >= 0.42 &&
            GFLooksLikeOpenedMaterialSubview(subview)) {
            subview.alpha = 0.0;
            subview.backgroundColor = UIColor.clearColor;
            subview.layer.backgroundColor = UIColor.clearColor.CGColor;
            continue;
        }

        GFSuppressOpenedMaterialRecursive(
            subview,
            glass,
            depth + 1
        );
    }
}

static CGFloat GFFloatyFolderCornerRadius(id floatyView) {
    if (!floatyView) {
        return 0.0;
    }

    SEL selector = NSSelectorFromString(@"cornerRadius");

    if (![floatyView respondsToSelector:selector]) {
        return 0.0;
    }

    IMP imp = [floatyView methodForSelector:selector];

    if (!imp) {
        return 0.0;
    }

    typedef double (*GFCornerRadiusIMP)(id, SEL);
    GFCornerRadiusIMP getter = (GFCornerRadiusIMP)imp;

    double value = getter(floatyView, selector);

    return MAX(0.0, (CGFloat)value);
}

static void GFRestoreStockPageBackground(UIView *pageView) {
    if (!pageView) {
        return;
    }

    GFOpenedFolderGlassView *glass = GFGetPageGlass(pageView);

    if (glass) {
        [glass removeFromSuperview];
        GFSetPageGlass(pageView, nil);
    }

    UIView *stock = GFStockBackgroundForPageView(pageView);

    if (stock) {
        stock.alpha = 1.0;
    }
}

/*
 * Configure one true SpringBoard page-background object.
 *
 * This function is intentionally idempotent; it is safe to call from
 * _newPageBackgroundView, layout, setBackgroundAlpha and setBackgroundEffect.
 */
static void GFConfigureOpenedPageBackground(id floatyView,
                                            UIView *pageView) {
    if (!pageView) {
        return;
    }

    if (!GFEnabled || GFStyle != 1) {
        GFRestoreStockPageBackground(pageView);
        return;
    }

    GFOpenedFolderGlassView *glass = GFGetPageGlass(pageView);

    if (!glass) {
        glass =
            [[GFOpenedFolderGlassView alloc]
                initWithStrength:GFGlassStrength];

        GFSetPageGlass(pageView, glass);

        /*
         * Keep the real page-background object and all of Apple's private
         * behavior. Our material is merely a visual child of that object.
         */
        [pageView addSubview:glass];
    }

    if (glass.superview != pageView) {
        [glass removeFromSuperview];
        [pageView addSubview:glass];
    }

    pageView.backgroundColor = UIColor.clearColor;
    pageView.layer.backgroundColor = UIColor.clearColor.CGColor;
    pageView.clipsToBounds = YES;
    pageView.layer.masksToBounds = YES;

    CGFloat radius = pageView.layer.cornerRadius;

    if (radius <= 0.0) {
        radius = GFFloatyFolderCornerRadius(floatyView);
    }

    if (radius <= 0.0) {
        radius =
            MIN(
                CGRectGetWidth(pageView.bounds),
                CGRectGetHeight(pageView.bounds)
            ) * 0.085;
    }

    if (radius > 0.0) {
        pageView.layer.cornerRadius = radius;
        pageView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    glass.frame = pageView.bounds;
    glass.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [glass setPreferredRadius:radius];

    /*
     * If the returned page is a clip view, its dedicated backgroundView is the
     * stock dark/blur material. Hide it immediately — before the caller can
     * present the page — which removes the old "black first, light second"
     * transition.
     */
    UIView *stock = GFStockBackgroundForPageView(pageView);

    if (stock && stock != pageView) {
        stock.alpha = 0.0;
        stock.backgroundColor = UIColor.clearColor;
        stock.layer.backgroundColor = UIColor.clearColor.CGColor;
    }

    /*
     * If the returned page itself is SBFolderBackgroundView, suppress its
     * full-size blur/tint children instead. This covers both historical
     * SpringBoard layouts without replacing Apple's object.
     */
    GFSuppressOpenedMaterialRecursive(
        pageView,
        glass,
        0
    );

    /*
     * Ensure the custom glass remains above the suppressed stock material.
     * Page-background objects do not contain app icons; icon lists are separate
     * siblings managed by SBFloatyFolderView.
     */
    [pageView bringSubviewToFront:glass];

    glass.alpha = 1.0;
}

static void GFConfigureRegisteredOpenedPages(id floatyView) {
    NSHashTable *table = GFOpenedPageSet(floatyView, NO);

    if (!table) {
        return;
    }

    for (UIView *pageView in table.allObjects) {
        GFConfigureOpenedPageBackground(
            floatyView,
            pageView
        );
    }
}


@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end

@interface SBFloatyFolderView : UIView
- (id)_newPageBackgroundView;
- (void)setBackgroundAlpha:(double)alpha;
- (void)setBackgroundEffect:(unsigned long long)effect;
- (double)cornerRadius;
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
 * Opened-folder hooks.
 *
 * The first-frame fix is `_newPageBackgroundView`: configure the real page
 * background immediately after SpringBoard constructs it and before it is
 * returned to the caller.
 *
 * `setBackgroundAlpha:` is left under Apple's control. Because our glass is a
 * child of the actual page background, the native transition automatically
 * animates it. After `%orig`, stock material is re-suppressed in case
 * SpringBoard updated its internal blur/tint alpha.
 */
%group GFOpenedFolderHooks

%hook SBFloatyFolderView

- (id)_newPageBackgroundView {
    id pageObject = %orig;

    if ([pageObject isKindOfClass:[UIView class]]) {
        UIView *pageView = (UIView *)pageObject;

        NSHashTable *table = GFOpenedPageSet(self, YES);
        [table addObject:pageView];

        GFConfigureOpenedPageBackground(
            self,
            pageView
        );
    }

    return pageObject;
}

- (void)layoutSubviews {
    %orig;

    GFConfigureRegisteredOpenedPages(self);
}

- (void)setBackgroundAlpha:(double)alpha {
    /*
     * Preserve Apple's transition timing and page-container opacity.
     * This is the critical difference from Beta4's `%orig(0.0)`.
     */
    %orig(alpha);

    GFConfigureRegisteredOpenedPages(self);
}

- (void)setBackgroundEffect:(unsigned long long)effect {
    %orig(effect);

    /*
     * SpringBoard can rebuild or retune its stock blur/tint when the effect
     * changes. Re-apply suppression synchronously, still before the next
     * CoreAnimation commit.
     */
    GFConfigureRegisteredOpenedPages(self);
}

%end

%end


%ctor {
    @autoreleasepool {
        GFLoadPreferences();

        if (objc_getClass("SBFolderIconImageView")) {
            %init(GFIconHooks);
        }

        Class floatyClass = objc_getClass("SBFloatyFolderView");

        /*
         * The opened-panel path depends on SpringBoard's real page-background
         * factory. If an unexpected system build removes that selector, keep
         * the closed-folder tweak active and simply skip opened customization
         * instead of trying to hook an unknown method.
         */
        if (floatyClass &&
            class_getInstanceMethod(
                floatyClass,
                NSSelectorFromString(@"_newPageBackgroundView")
            ) &&
            class_getInstanceMethod(
                floatyClass,
                NSSelectorFromString(@"setBackgroundAlpha:")
            )) {
            %init(GFOpenedFolderHooks);
        }
    }
}
