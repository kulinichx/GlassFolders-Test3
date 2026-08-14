#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>

/*
 * GlassFolders 0.7.4 Beta 2.4 — Clear strength-as-blur + locked Liquid Glass baselines
 *
 * Scope:
 * - stable closed SpringBoard folder icon path
 * - opened panel attached only to SBFolderBackgroundView
 * - reuses SBHLibraryCategoryPodBackgroundView as a read-only visual layer
 * - no App Library controller / transition / page-factory hooks
 *
 * Optical model:
 * - wallpaper-only chroma: no purple/blue chromatic body tint
 * - Clear opened panel uses a thin neutral-white optical lift, never a hue tint
 * - oversized opened-folder backdrop sampling before final rounded clipping
 * - stronger CABackdropLayer for wallpaper color / blur / saturation
 * - native App Library category-pod view reused passively in closed folders
 * - cached rounded-rect SDF lighting
 * - one continuous equal-brightness upper-left -> top specular rail
 * - one continuous equal-brightness bottom -> lower-right specular rail
 * - positional endpoint gates before upper-right / lower-left corners
 * - deliberately quiet straight left/right side middles
 * - subtle upper-right / lower-left transition structure
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


/*
 * Clear has a different slider contract from Liquid Glass.
 *
 * In Clear, Glass Strength is primarily the LOCAL BLUR amount.  The white
 * transmission/highlight system reaches its normal Clear appearance early
 * and then stays almost constant, so raising the slider does not turn Clear
 * into a brighter/whiter version of itself.
 *
 * 0%   -> no local Clear blur
 * 25%  -> ~29% of the Clear blur ceiling
 * 50%  -> ~54%
 * 55%  -> ~58%
 * 75%  -> ~77%
 * 100% -> full Clear blur ceiling
 */
static inline CGFloat GFClearBlurResponse(CGFloat strength) {
    return pow(GFClamp01(strength), 0.90);
}


/*
 * Non-blur Clear optics are only softly gated by the first 15% of the slider.
 * Above that point the slider is effectively a blur control.  The smootherstep
 * avoids a visible pop when moving away from 0%.
 */
static inline CGFloat GFClearActivationResponse(CGFloat strength) {
    CGFloat t = GFClamp01(strength / 0.15);
    return t * t * (3.0 - 2.0 * t);
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
                     * Beta 1.6 continuous specular rails.
                     *
                     * Apple-like topology:
                     *
                     *   PRIMARY RAIL
                     *     upper-left rounded corner -> entire top edge
                     *
                     *   SECONDARY RAIL
                     *     entire bottom edge -> lower-right rounded corner
                     *
                     * Each pair shares ONE mask and ONE luminance gain. This
                     * removes the "bright corner + separate bright line"
                     * appearance. The highlight now visually turns through the
                     * radius as one continuous piece of glass.
                     *
                     * Straight left/right side middles remain deliberately
                     * quiet and receive only a low structural floor.
                     */
                    CGFloat verticalEdge =
                        pow(fabs(nx), 2.30);

                    CGFloat topFacing =
                        MAX(0.0, -ny);

                    CGFloat bottomFacing =
                        MAX(0.0, ny);

                    CGFloat leftFacing =
                        MAX(0.0, -nx);

                    CGFloat rightFacing =
                        MAX(0.0, nx);

                    /*
                     * Saturate near the middle of the target corner so the
                     * curved portion reaches the SAME peak as its adjoining
                     * straight rail instead of becoming an isolated hotspot.
                     */
                    CGFloat topLeftCornerSelector =
                        GFClamp01(
                            2.10 * leftFacing * topFacing
                        );

                    CGFloat bottomRightCornerSelector =
                        GFClamp01(
                            2.10 * rightFacing * bottomFacing
                        );

                    CGFloat topRightCornerSelector =
                        GFClamp01(
                            2.05 * rightFacing * topFacing
                        );

                    CGFloat bottomLeftCornerSelector =
                        GFClamp01(
                            2.05 * leftFacing * bottomFacing
                        );

                    CGFloat topLeftCornerBridge =
                        pow(topLeftCornerSelector, 0.58);

                    CGFloat bottomRightCornerBridge =
                        pow(bottomRightCornerSelector, 0.58);

                    CGFloat topRightTransition =
                        pow(topRightCornerSelector, 0.88);

                    CGFloat bottomLeftTransition =
                        pow(bottomLeftCornerSelector, 0.88);

                    /*
                     * ONE continuous equal-brightness mask:
                     *
                     * - topFacing is 1.0 on the straight top edge;
                     * - topLeftCornerBridge rises to ~1.0 through the TL arc;
                     * - MAX() makes the joint behave as one rail.
                     *
                     * Same construction for bottom -> lower-right.
                     */
                    /*
                     * Raw joined rails before endpoint ownership is applied.
                     * The TL/top pair and bottom/BR pair still share exactly
                     * one geometric mask and one luminance gain.
                     */
                    CGFloat primaryRailRaw =
                        GFClamp01(
                            MAX(
                                pow(topFacing, 1.08),
                                topLeftCornerBridge
                            )
                        );

                    CGFloat secondaryRailRaw =
                        GFClamp01(
                            MAX(
                                pow(bottomFacing, 1.08),
                                bottomRightCornerBridge
                            )
                        );

                    /*
                     * Beta 1.7 endpoint ownership.
                     *
                     * Normal direction alone cannot distinguish "top straight"
                     * from the upper-right radius: both still have -ny.
                     * Use pixel position to detect entry into the opposite
                     * corner radius, then smoothly attenuate only that end.
                     *
                     * Primary:
                     *   TL corner + full top = 100%
                     *   entering TR radius   = fade
                     *   far TR end           = 12%
                     *
                     * Secondary:
                     *   far BL end           = 12%
                     *   leaving BL radius    = fade up
                     *   full bottom + BR     = 100%
                     */
                    CGFloat endpointRadius =
                        MAX(
                            1.0,
                            MIN(
                                radius,
                                0.5 * MIN(width, height)
                            )
                        );

                    CGFloat rightArcProgress =
                        GFClamp01(
                            (
                                x -
                                (width - endpointRadius)
                            ) /
                            endpointRadius
                        );

                    CGFloat leftArcProgress =
                        GFClamp01(
                            (
                                endpointRadius - x
                            ) /
                            endpointRadius
                        );

                    CGFloat rightArcSmooth =
                        rightArcProgress *
                        rightArcProgress *
                        (
                            3.0 -
                            2.0 * rightArcProgress
                        );

                    CGFloat leftArcSmooth =
                        leftArcProgress *
                        leftArcProgress *
                        (
                            3.0 -
                            2.0 * leftArcProgress
                        );

                    CGFloat primaryEndpointGate =
                        1.0 -
                        0.88 * rightArcSmooth;

                    CGFloat secondaryEndpointGate =
                        1.0 -
                        0.88 * leftArcSmooth;

                    CGFloat primaryRailMask =
                        primaryRailRaw *
                        primaryEndpointGate;

                    CGFloat secondaryRailMask =
                        secondaryRailRaw *
                        secondaryEndpointGate;

                    /*
                     * Remove rail-owned regions from the straight vertical
                     * side mask. The endpoint-faded TR/BL areas are permitted
                     * to retain only a small structural side cue.
                     */
                    CGFloat coveredByRails =
                        MAX(
                            primaryRailMask,
                            secondaryRailMask
                        );

                    CGFloat sideMiddleMask =
                        verticalEdge *
                        pow(
                            MAX(0.0, 1.0 - coveredByRails),
                            1.55
                        );

                    CGFloat perimeterFloor =
                        0.0040 + 0.0060 * edgeDrive;

                    /*
                     * Primary rail = top + upper-left, same gain everywhere.
                     * Secondary rail = bottom + lower-right, same gain
                     * everywhere. Secondary remains slightly softer than
                     * primary, but there is no discontinuity inside either
                     * pair.
                     */
                    CGFloat primaryFilamentGain =
                        0.030 + 0.360 * edgeDrive;

                    CGFloat primaryCoreGain =
                        0.010 + 0.110 * edgeDrive;

                    CGFloat primaryShoulderGain =
                        0.005 + 0.038 * edgeDrive;

                    CGFloat secondaryFilamentGain =
                        0.018 + 0.270 * edgeDrive;

                    CGFloat secondaryCoreGain =
                        0.007 + 0.078 * edgeDrive;

                    CGFloat secondaryShoulderGain =
                        0.0035 + 0.025 * edgeDrive;

                    /*
                     * Straight sides are now only a silhouette cue.
                     */
                    CGFloat sideMiddleGain =
                        0.0010 + 0.0090 * edgeDrive;

                    /*
                     * Upper-right and lower-left are non-dominant transition
                     * corners. They remain visible enough to keep the rounded
                     * shape coherent, without becoming a third/fourth hotspot.
                     */
                    CGFloat transitionCornerGain =
                        0.0015 + 0.010 * edgeDrive;

                    /*
                     * Keep directional physics only as a very small micro
                     * modulation. The 4% range is intentionally too small to
                     * make the upper-left brighter than the top rail, so the
                     * joined rail still reads as one brightness.
                     */
                    CGFloat primaryDirectionalMicro =
                        0.96 + 0.04 * pow(facing, 1.20);

                    CGFloat secondaryDirectionalMicro =
                        0.96 + 0.04 * pow(opposite, 1.20);

                    CGFloat white =
                        filament * perimeterFloor +

                        shoulder * primaryRailMask *
                            primaryShoulderGain +
                        core * primaryRailMask *
                            primaryCoreGain +
                        filament * primaryRailMask *
                            primaryFilamentGain *
                            primaryDirectionalMicro +

                        shoulder * secondaryRailMask *
                            secondaryShoulderGain +
                        core * secondaryRailMask *
                            secondaryCoreGain +
                        filament * secondaryRailMask *
                            secondaryFilamentGain *
                            secondaryDirectionalMicro +

                        filament * sideMiddleMask *
                            sideMiddleGain +

                        filament *
                            (topRightTransition +
                             bottomLeftTransition) *
                            transitionCornerGain +

                        /*
                         * A thin far-side filament follows the SAME secondary
                         * bottom/lower-right rail rather than lighting the
                         * entire right wall.
                         */
                        secondaryFilament *
                            secondaryRimGain *
                            secondaryRailMask *
                            0.36;

                    CGFloat shadowOffset =
                        (insideDepth - shadowCenter) /
                        MAX(0.001, shadowWidth);

                    CGFloat shadowBand =
                        exp(-(shadowOffset * shadowOffset * 1.20));

                    CGFloat darkStructureMask =
                        0.78 * secondaryRailMask +
                        0.18 * sideMiddleMask +
                        0.04 * (
                            topRightTransition +
                            bottomLeftTransition
                        );

                    CGFloat dark =
                        shadowBand *
                        shadowGain *
                        (0.92 + 0.08 * pow(opposite, 1.20)) *
                        darkStructureMask;

                    signedLight += white - dark;
                }
            }

            /*
             * High percentages are intentionally allowed a much brighter
             * optical peak. The clamp itself now participates in the slider
             * response instead of capping 75% and 100% at the same ceiling.
             */
            CGFloat closedEdgePeak =
                0.160 + 0.500 * edgeDrive;

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




#pragma mark - Native App Library category-pod visual reuse

/*
 * This is the targeted path for matching Apple's App Library card body.
 *
 * SBHLibraryCategoryPodBackgroundView is the actual SpringBoardHome class
 * used for App Library category backgrounds.  Rather than guessing its
 * private MaterialKit recipe, we instantiate a separate copy and let
 * SpringBoard's own SBHVisualStylingView machinery configure it.
 *
 * Important: this does NOT hook or alter the real App Library.  It only
 * creates an independent visual view of the same class inside our folder
 * background container.  If the class cannot be created, the stronger
 * CABackdrop fallback remains fully functional.
 */
static UIView *GFCreateNativeAppLibraryPodVisual(CGFloat strength) {
    Class podClass = NSClassFromString(@"SBHLibraryCategoryPodBackgroundView");

    if (!podClass || ![podClass isSubclassOfClass:[UIView class]]) {
        return nil;
    }

    UIView *podView = nil;

    @try {
        podView = [[podClass alloc] initWithFrame:CGRectZero];
    } @catch (__unused NSException *exception) {
        podView = nil;
    }

    if (![podView isKindOfClass:[UIView class]]) {
        return nil;
    }

    podView.userInteractionEnabled = NO;
    podView.clipsToBounds = YES;
    podView.layer.masksToBounds = YES;

    /*
     * The native App Library visual sits over our wallpaper-preserving
     * CABackdrop body.  Partial alpha intentionally makes the desktop folder
     * a little more luminous than the older stock folder while avoiding an
     * opaque card.  Strength still has visible authority.
     */
    CGFloat materialResponse = GFMaterialResponse(strength);

    /*
     * Beta 2.1: restore the lighter closed-folder Liquid Glass appearance.
     * The stronger native pod participation introduced later made the closed
     * icon read visibly darker on-device.  This is the earlier, proven blend
     * used by the lighter reference: no hue tint, just less native material
     * stacked over the wallpaper backdrop.
     */
    podView.alpha = MIN(0.78, 0.42 + 0.36 * materialResponse);

    return podView;
}


@interface GFBackdropGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) UIView *gfAppLibraryPodVisual;
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
        CGFloat clearBlurResponse = GFClearBlurResponse(_gfStrength);
        CGFloat clearActivation = GFClearActivationResponse(_gfStrength);

        if (_gfStrength > 0.001 && isBackdropLayer) {
            /*
             * Preserve wallpaper color instead of whitening it.
             * At 45–55%, blur stays moderate while saturation is boosted.
             */
            CGFloat blurRadius;
            CGFloat saturation;
            CGFloat brightness;

            if (_gfStyle == 1) {
                blurRadius = 4.8 + (7.5 * materialResponse);
                saturation = 1.08 + (0.20 * materialResponse);
                brightness = 0.006 + (0.014 * materialResponse);
            } else {
                /*
                 * Clear closed-folder semantics match the opened panel: the
                 * slider primarily changes blur.  8.40 * response preserves
                 * the old accepted 55% closed-Clear blur (~4.9 pt) while
                 * saturation settles early instead of climbing with strength.
                 */
                blurRadius = 8.40 * clearBlurResponse;
                saturation = 1.120 + (0.055 * clearActivation);
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
            UIBlurEffectStyle fallbackStyle =
                (_gfStyle == 1)
                    ? UIBlurEffectStyleSystemThinMaterial
                    : UIBlurEffectStyleSystemUltraThinMaterial;

            UIBlurEffect *effect =
                [UIBlurEffect effectWithStyle:fallbackStyle];

            _gfFallbackBlurView =
                [[UIVisualEffectView alloc] initWithEffect:effect];

            _gfFallbackBlurView.userInteractionEnabled = NO;
            _gfFallbackBlurView.alpha =
                (_gfStyle == 1) ? MIN(0.86, 0.56 + 0.30 * materialResponse)
                                : 0.30 * clearActivation;

            [self addSubview:_gfFallbackBlurView];
        }

        /*
         * Neutral optical transmission only. No hue is introduced here:
         * wallpaper/backdrop remains the sole color source. Liquid Glass
         * restores the proven Beta1.8 light-body lift that produced the
         * user's accepted closed-folder reference.
         */
        CGFloat tintAlpha = 0.0;

        if (_gfStrength > 0.001) {
            tintAlpha = (_gfStyle == 1)
                ? 0.030 + (0.060 * tintResponse)
                : 0.010 * clearActivation;
        }

        if (tintAlpha > 0.001) {
            _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
            _gfTintView.userInteractionEnabled = NO;
            _gfTintView.backgroundColor = UIColor.whiteColor;
            _gfTintView.alpha = tintAlpha;
            [self addSubview:_gfTintView];
        }

        if (_gfStyle == 1 && _gfStrength > 0.001) {
            _gfAppLibraryPodVisual =
                GFCreateNativeAppLibraryPodVisual(_gfStrength);


            if (_gfAppLibraryPodVisual) {
                if (_gfTintView) {
                    [self insertSubview:_gfAppLibraryPodVisual
                           belowSubview:_gfTintView];
                } else {
                    [self addSubview:_gfAppLibraryPodVisual];
                }
            }

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
    self.gfAppLibraryPodVisual.frame = self.bounds;
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

        if (self.gfAppLibraryPodVisual) {
            self.gfAppLibraryPodVisual.layer.cornerRadius = radius;
            self.gfAppLibraryPodVisual.layer.cornerCurve = kCACornerCurveContinuous;
            self.gfAppLibraryPodVisual.layer.masksToBounds = YES;

        }
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
                                                 NSInteger style,
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
        @"P23-%@-%@-%zux%zu-r%.2f-s%ld",
        (style == 1) ? @"LG" : @"CL",
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

    BOOL clearStyle = (style == 0);
    CGFloat clearActivation = clearStyle
        ? GFClearActivationResponse(strength)
        : 1.0;

    /*
     * Clear edge optics are intentionally almost strength-independent.
     * 0.62 matches the old Clear look around the user's 55% baseline; after
     * the first 15% only the blur continues to grow materially.
     */
    CGFloat e = clearStyle
        ? (0.62 * clearActivation)
        : GFSpecularResponse(strength);

    /*
     * Clear and Liquid Glass intentionally use different edge optics.
     * Clear is a thin transparent sheet: a broader, softer white shoulder,
     * very little hard filament, and almost no dark thickness shoulder.
     * Liquid Glass keeps the existing narrower/high-energy rail.
     *
     * These are neutral-white optics only. No hue is introduced here.
     */
    CGFloat shoulderWidth =
        (clearStyle
            ? (10.4 + 2.6 * e)
            : (8.0 + 2.4 * e)) * renderScale;

    CGFloat coreWidth =
        (clearStyle
            ? (2.00 + 0.40 * e)
            : (1.30 + 0.34 * e)) * renderScale;

    CGFloat filamentWidth =
        (clearStyle
            ? (0.82 + 0.12 * e)
            : (0.62 + 0.12 * e)) * renderScale;

    CGFloat secondaryRimWidth =
        (clearStyle
            ? (1.02 + 0.15 * e)
            : (0.78 + 0.12 * e)) * renderScale;

    CGFloat secondaryRimGain;
    if (clearStyle) {
        secondaryRimGain = darkAppearance
            ? (0.034 + 0.014 * e)
            : (0.026 + 0.011 * e);
    } else {
        secondaryRimGain = darkAppearance
            ? (0.092 + 0.032 * e)
            : (0.082 + 0.030 * e);
    }

    CGFloat darkShoulderCenter =
        (clearStyle
            ? (3.15 + 0.55 * e)
            : (2.8 + 0.5 * e)) * renderScale;

    CGFloat darkShoulderWidth =
        (clearStyle
            ? (3.00 + 0.60 * e)
            : (2.4 + 0.5 * e)) * renderScale;

    CGFloat darkShoulderGain;
    if (clearStyle) {
        darkShoulderGain = darkAppearance
            ? (0.0010 + 0.0010 * e)
            : (0.0030 + 0.0015 * e);
    } else {
        darkShoulderGain = darkAppearance
            ? (0.008 + 0.003 * e)
            : (0.020 + 0.005 * e);
    }

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
            CGFloat opposite = MAX(0.0, -ndotl);

            CGFloat shoulderRatio =
                insideDepth / MAX(0.001, shoulderWidth);

            CGFloat coreRatio =
                insideDepth / MAX(0.001, coreWidth);

            /*
             * Beta 2.1: keep the directional optical filament slightly
             * INSIDE the host's native continuous-corner clip.  The host is
             * kCACornerCurveContinuous (a squircle-like curve), while this
             * lightweight CPU texture uses an analytic rounded-rect field.
             * Centering the filament ~0.6-0.8 pt inward prevents the raster
             * highlight from grazing the clip exactly at corner/edge tangents.
             * A very low native CALayer border below provides the exact
             * continuous-curve continuity floor.
             */
            CGFloat filamentInset =
                ((style == 1) ? 0.78 : 0.58) * renderScale;

            CGFloat secondaryInset =
                ((style == 1) ? 0.82 : 0.60) * renderScale;

            CGFloat filamentRatio =
                fabs(insideDepth - filamentInset) /
                MAX(0.001, filamentWidth);

            CGFloat secondaryRatio =
                fabs(insideDepth - secondaryInset) /
                MAX(0.001, secondaryRimWidth);

            CGFloat shoulder =
                exp(-(shoulderRatio * shoulderRatio));

            CGFloat core =
                exp(-(coreRatio * coreRatio * 1.30));

            CGFloat filament =
                exp(-pow(filamentRatio, 2.55));

            CGFloat secondary =
                exp(-pow(secondaryRatio, 2.30));

            /*
             * Beta 1.6 opened-panel continuous rails.
             *
             * The larger opened surface uses exactly the same optical
             * topology as the closed folder:
             *
             *   primary:
             *     upper-left rounded corner -> full top rail
             *
             *   secondary:
             *     full bottom rail -> lower-right rounded corner
             *
             * Corner and straight segment inside each pair use one shared
             * mask/gain so their brightness is continuous through the radius.
             * The large panel is broader/softer, not differently organized.
             */
            CGFloat edgeDrive = clearStyle
                ? (0.36 * clearActivation)
                : GFEdgeResponse(strength);

            CGFloat verticalEdge =
                pow(fabs(nx), 2.32);

            CGFloat topFacing =
                MAX(0.0, -ny);

            CGFloat bottomFacing =
                MAX(0.0, ny);

            CGFloat leftFacing =
                MAX(0.0, -nx);

            CGFloat rightFacing =
                MAX(0.0, nx);

            CGFloat topRightCornerSelector =
                GFClamp01(
                    2.05 * rightFacing * topFacing
                );

            CGFloat bottomLeftCornerSelector =
                GFClamp01(
                    2.05 * leftFacing * bottomFacing
                );

            CGFloat topRightTransition =
                pow(topRightCornerSelector, 0.90);

            CGFloat bottomLeftTransition =
                pow(bottomLeftCornerSelector, 0.90);

            CGFloat endpointRadius =
                MAX(
                    1.0,
                    MIN(
                        radius,
                        0.5 * MIN(width, height)
                    )
                );

            /*
             * Beta 2.4 — locked symmetric continuous tangent rails.
             *
             * Do not splice a "corner mask" into a separate straight-edge
             * mask. The SDF normal is already unit length, so in the owned
             * upper-left quadrant:
             *
             *     hypot(topFacing, leftFacing) == 1
             *
             * from the top straight, through every point of the TL arc, to
             * the left straight. The same identity holds for the mirrored
             * lower-right quadrant. Using that invariant gives one energy-flat
             * optical rail across BOTH tangents instead of pieces which only
             * happen to overlap.
             *
             * Geometry is an exact 180-degree mirror:
             *
             *   primary   : top -> TL arc -> left tail
             *   secondary : bottom -> BR arc -> right tail
             *
             * Dark/light appearance may change gain later, but never this
             * geometry. The connection/fade relationship is therefore
             * identical in both appearance modes.
             */
            CGFloat primaryQuadrantEnergy =
                GFClamp01(
                    hypot(topFacing, leftFacing)
                );

            CGFloat secondaryQuadrantEnergy =
                GFClamp01(
                    hypot(bottomFacing, rightFacing)
                );

            /*
             * Do not hold the side tangent at exactly the same energy as the
             * top/bottom rail and then suddenly begin fading.  Ease the last
             * part of each owned corner by only 6%, then continue that same
             * value into the long side tail.  This makes top->TL->left and
             * bottom->BR->right feel like one reflection turning a corner.
             */
            CGFloat primaryTurn = leftFacing /
                MAX(0.001, topFacing + leftFacing);
            CGFloat secondaryTurn = rightFacing /
                MAX(0.001, bottomFacing + rightFacing);

            CGFloat primaryTurnT =
                GFClamp01((primaryTurn - 0.48) / 0.52);
            CGFloat secondaryTurnT =
                GFClamp01((secondaryTurn - 0.48) / 0.52);

            CGFloat primaryTurnSmooth =
                primaryTurnT * primaryTurnT * primaryTurnT *
                (primaryTurnT * (primaryTurnT * 6.0 - 15.0) + 10.0);
            CGFloat secondaryTurnSmooth =
                secondaryTurnT * secondaryTurnT * secondaryTurnT *
                (secondaryTurnT * (secondaryTurnT * 6.0 - 15.0) + 10.0);

            CGFloat primaryTurnGain = 1.0 - 0.060 * primaryTurnSmooth;
            CGFloat secondaryTurnGain = 1.0 - 0.060 * secondaryTurnSmooth;

            CGFloat tangentOverlap =
                MAX(
                    1.35 * renderScale,
                    endpointRadius * 0.032
                );

            /*
             * Apple-like turn-off: after the TL/BR tangent the reflection
             * must breathe along the side instead of collapsing within half
             * a radius.  The two sides are exact mirrors.
             */
            CGFloat sideTailLength =
                MAX(
                    22.0 * renderScale,
                    endpointRadius * 1.12
                );

            /*
             * Keep full energy for a tiny distance AFTER each tangent. The
             * fade begins only outside that overlap, so the tangent itself can
             * never be a fade endpoint. This removes the hairline dip at
             * TL<->top and BR<->bottom while preserving a natural side fade.
             */
            CGFloat topEnvelope =
                (y <= endpointRadius + tangentOverlap)
                    ? 1.0
                    : 0.0;

            CGFloat bottomEnvelope =
                (y >= height - endpointRadius - tangentOverlap)
                    ? 1.0
                    : 0.0;

            CGFloat topLeftFadeStart =
                endpointRadius + tangentOverlap;

            CGFloat bottomRightFadeStart =
                height - endpointRadius - tangentOverlap;

            CGFloat topLeftTailProgress =
                GFClamp01(
                    (y - topLeftFadeStart) /
                    MAX(1.0, sideTailLength)
                );

            CGFloat bottomRightTailProgress =
                GFClamp01(
                    (bottomRightFadeStart - y) /
                    MAX(1.0, sideTailLength)
                );

            /* C2-continuous smootherstep: 6t^5 - 15t^4 + 10t^3. */
            CGFloat tlT = topLeftTailProgress;
            CGFloat brT = bottomRightTailProgress;

            CGFloat topLeftTailSmooth =
                tlT * tlT * tlT *
                (tlT * (tlT * 6.0 - 15.0) + 10.0);

            CGFloat bottomRightTailSmooth =
                brT * brT * brT *
                (brT * (brT * 6.0 - 15.0) + 10.0);

            CGFloat leftTailEnvelope =
                (y <= topLeftFadeStart)
                    ? 1.0
                    : ((y <= topLeftFadeStart + sideTailLength)
                        ? (1.0 - topLeftTailSmooth)
                        : 0.0);

            CGFloat rightTailEnvelope =
                (y >= bottomRightFadeStart)
                    ? 1.0
                    : ((y >= bottomRightFadeStart - sideTailLength)
                        ? (1.0 - bottomRightTailSmooth)
                        : 0.0);

            /*
             * At TL the top and left envelopes overlap at exactly 1.0; at BR
             * the bottom and right envelopes do the same. MAX cannot create a
             * valley at an internal join. Only the true side tail may fade.
             */
            CGFloat primaryEnvelope =
                MAX(topEnvelope, leftTailEnvelope);

            CGFloat secondaryEnvelope =
                MAX(bottomEnvelope, rightTailEnvelope);

            /*
             * Free endpoints remain soft: primary rolls away through the TR
             * arc, secondary through the BL arc. Use a C2 gate here too so the
             * opposite corners never introduce a hard shoulder.
             */
            CGFloat rightArcProgress =
                GFClamp01(
                    (x - (width - endpointRadius)) /
                    endpointRadius
                );

            CGFloat leftArcProgress =
                GFClamp01(
                    (endpointRadius - x) /
                    endpointRadius
                );

            CGFloat rr = rightArcProgress;
            CGFloat lr = leftArcProgress;

            CGFloat rightArcSmooth =
                rr * rr * rr *
                (rr * (rr * 6.0 - 15.0) + 10.0);

            CGFloat leftArcSmooth =
                lr * lr * lr *
                (lr * (lr * 6.0 - 15.0) + 10.0);

            CGFloat primaryEndpointGate =
                1.0 - 0.88 * rightArcSmooth;

            CGFloat secondaryEndpointGate =
                1.0 - 0.88 * leftArcSmooth;

            CGFloat primaryRailMask =
                GFClamp01(
                    primaryQuadrantEnergy *
                    primaryTurnGain *
                    primaryEnvelope *
                    primaryEndpointGate
                );

            CGFloat secondaryRailMask =
                GFClamp01(
                    secondaryQuadrantEnergy *
                    secondaryTurnGain *
                    secondaryEnvelope *
                    secondaryEndpointGate
                );

            CGFloat coveredByRails =
                MAX(
                    primaryRailMask,
                    secondaryRailMask
                );

            CGFloat sideMiddleMask =
                verticalEdge *
                pow(
                    MAX(0.0, 1.0 - coveredByRails),
                    1.60
                );

            CGFloat perimeterFloor = darkAppearance
                ? 0.0048
                : 0.0035;

            /*
             * Liquid Glass keeps the existing high-energy rail. Clear gets a
             * separate broad/soft rail so it does not read as "Liquid Glass
             * with less blur".  Dark appearance needs more white definition;
             * light appearance deliberately backs it off.
             */
            CGFloat primaryFilamentGain;
            CGFloat primaryCoreGain;
            CGFloat primaryShoulderGain;
            CGFloat secondaryFilamentGain;
            CGFloat secondaryCoreGain;
            CGFloat secondaryShoulderGain;
            CGFloat sideMiddleGain;
            CGFloat transitionCornerGain;

            if (clearStyle) {
                primaryFilamentGain = darkAppearance
                    ? (0.010 + 0.075 * edgeDrive)
                    : (0.008 + 0.055 * edgeDrive);

                primaryCoreGain = darkAppearance
                    ? (0.014 + 0.055 * edgeDrive)
                    : (0.010 + 0.040 * edgeDrive);

                primaryShoulderGain = darkAppearance
                    ? (0.015 + 0.045 * edgeDrive)
                    : (0.011 + 0.034 * edgeDrive);

                secondaryFilamentGain = darkAppearance
                    ? (0.007 + 0.052 * edgeDrive)
                    : (0.005 + 0.038 * edgeDrive);

                secondaryCoreGain = darkAppearance
                    ? (0.009 + 0.038 * edgeDrive)
                    : (0.006 + 0.028 * edgeDrive);

                secondaryShoulderGain = darkAppearance
                    ? (0.009 + 0.032 * edgeDrive)
                    : (0.006 + 0.023 * edgeDrive);

                sideMiddleGain = darkAppearance
                    ? (0.0010 + 0.0040 * edgeDrive)
                    : (0.0008 + 0.0030 * edgeDrive);

                transitionCornerGain = darkAppearance
                    ? (0.0013 + 0.0050 * edgeDrive)
                    : (0.0010 + 0.0038 * edgeDrive);
            } else {
                primaryFilamentGain = darkAppearance
                    ? (0.036 + 0.300 * edgeDrive)
                    : (0.027 + 0.215 * edgeDrive);

                primaryCoreGain = darkAppearance
                    ? (0.014 + 0.090 * edgeDrive)
                    : (0.010 + 0.064 * edgeDrive);

                primaryShoulderGain = darkAppearance
                    ? (0.008 + 0.035 * edgeDrive)
                    : (0.006 + 0.025 * edgeDrive);

                secondaryFilamentGain = darkAppearance
                    ? (0.024 + 0.220 * edgeDrive)
                    : (0.018 + 0.158 * edgeDrive);

                secondaryCoreGain = darkAppearance
                    ? (0.009 + 0.064 * edgeDrive)
                    : (0.0065 + 0.046 * edgeDrive);

                secondaryShoulderGain = darkAppearance
                    ? (0.005 + 0.023 * edgeDrive)
                    : (0.0035 + 0.017 * edgeDrive);

                sideMiddleGain = darkAppearance
                    ? (0.0018 + 0.010 * edgeDrive)
                    : (0.0015 + 0.008 * edgeDrive);

                transitionCornerGain = darkAppearance
                    ? (0.0025 + 0.012 * edgeDrive)
                    : (0.0020 + 0.009 * edgeDrive);
            }

            /*
             * Only a tiny directional micro-variation survives. This keeps
             * the TL arc and top segment visually equal instead of making the
             * 45-degree corner peak brighter.
             */
            /*
             * The opened panel rail is intentionally energy-flat through an
             * internal tangent.  Direction still shapes the non-owned corner
             * transitions, but it must not create a 1-4% dip exactly where a
             * curved rail becomes a straight one.
             */
            CGFloat primaryDirectionalMicro = 1.0;
            CGFloat secondaryDirectionalMicro = 1.0;

            CGFloat white =
                filament * perimeterFloor +

                shoulder * primaryRailMask *
                    primaryShoulderGain +
                core * primaryRailMask *
                    primaryCoreGain +
                filament * primaryRailMask *
                    primaryFilamentGain *
                    primaryDirectionalMicro +

                shoulder * secondaryRailMask *
                    secondaryShoulderGain +
                core * secondaryRailMask *
                    secondaryCoreGain +
                filament * secondaryRailMask *
                    secondaryFilamentGain *
                    secondaryDirectionalMicro +

                filament * sideMiddleMask *
                    sideMiddleGain +

                filament *
                    (topRightTransition +
                     bottomLeftTransition) *
                    transitionCornerGain +

                /*
                 * Far-side white reflection is confined to the secondary
                 * bottom/lower-right rail, not the straight right wall.
                 */
                secondary *
                    secondaryRimGain *
                    secondaryRailMask *
                    (0.32 + 0.18 * edgeDrive);

            /*
             * Far-side thickness starts inside the edge.  It never occupies
             * the same pixels as the secondary white filament.
             */
            CGFloat shadowOffset =
                (insideDepth - darkShoulderCenter) /
                MAX(0.001, darkShoulderWidth);

            CGFloat darkStructureMask =
                0.78 * secondaryRailMask +
                0.18 * sideMiddleMask +
                0.04 * (
                    topRightTransition +
                    bottomLeftTransition
                );

            CGFloat dark =
                exp(-(shadowOffset * shadowOffset * 1.10)) *
                darkShoulderGain *
                (0.92 + 0.08 * pow(opposite, 1.15)) *
                darkStructureMask;

            CGFloat edgePeak;
            if (clearStyle) {
                edgePeak = darkAppearance
                    ? (0.130 + 0.140 * edgeDrive)
                    : (0.100 + 0.100 * edgeDrive);
            } else {
                edgePeak = darkAppearance
                    ? (0.215 + 0.275 * edgeDrive)
                    : (0.162 + 0.202 * edgeDrive);
            }

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


@interface GFPanelBackdropSampleView : UIView
@end

@implementation GFPanelBackdropSampleView

+ (Class)layerClass {
    Class backdropClass =
        NSClassFromString(@"CABackdropLayer");

    return backdropClass ?: [CALayer class];
}

@end


@interface GFPanelGlassView : UIView
@property (nonatomic, strong) GFPanelBackdropSampleView *gfBackdropSampleView;
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CALayer *gfOpticalLayer;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) NSInteger gfStyle;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) CGSize gfLightingSize;
@property (nonatomic, assign) CGFloat gfLightingRadius;
@property (nonatomic, assign) BOOL gfLastDarkAppearance;
@property (nonatomic, assign) BOOL gfHasAppearance;
@property (nonatomic, assign) CGFloat gfBackdropOverscan;
- (instancetype)initWithStyle:(NSInteger)style
                     strength:(CGFloat)strength;
- (void)setPreferredRadius:(CGFloat)radius;
- (void)gfRefreshMaterial;
@end


@implementation GFPanelGlassView

- (instancetype)initWithStyle:(NSInteger)style
                     strength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStyle = (style == 1) ? 1 : 0;
        _gfStrength =
            MIN(1.0, MAX(0.0, strength));

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.layer.allowsEdgeAntialiasing = YES;

        /*
         * Sample beyond the final rounded mask.  Blurring a backdrop whose
         * sample bounds end exactly at the rounded rect causes the blur kernel
         * to clamp at the top-left / lower-right arc and creates the visible
         * seam the screenshots showed.  The parent clips only after filtering.
         */
        _gfBackdropOverscan = 30.0;
        _gfBackdropSampleView =
            [[GFPanelBackdropSampleView alloc] initWithFrame:CGRectZero];
        _gfBackdropSampleView.userInteractionEnabled = NO;
        _gfBackdropSampleView.backgroundColor = UIColor.clearColor;
        _gfBackdropSampleView.clipsToBounds = NO;
        _gfBackdropSampleView.layer.masksToBounds = NO;
        [self addSubview:_gfBackdropSampleView];

        /*
         * Intentionally colorless.  All hue comes from the wallpaper/backdrop.
         * Keep the view only so older code paths can address it safely.
         */
        _gfTintView =
            [[UIView alloc] initWithFrame:CGRectZero];

        _gfTintView.userInteractionEnabled = NO;
        _gfTintView.backgroundColor = UIColor.clearColor;
        _gfTintView.alpha = 0.0;

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
        _gfOpticalLayer.zPosition = 20.0;

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

    CGFloat clearBlurResponse =
        GFClearBlurResponse(self.gfStrength);

    CGFloat clearActivation =
        GFClearActivationResponse(self.gfStrength);

    CALayer *materialLayer =
        self.gfBackdropSampleView.layer;

    BOOL isBackdropLayer =
        [NSStringFromClass(materialLayer.class)
            containsString:@"Backdrop"];

    if (self.gfStrength > 0.001 &&
        isBackdropLayer) {

        /*
         * Style-specific opened material. Chroma always comes from
         * the wallpaper/backdrop. A neutral brightness adjustment is allowed
         * for Liquid Glass in dark appearance so a large blur kernel does not
         * collapse the panel into black; no purple/blue/pink tint is added.
         */
        CGFloat blurRadius;
        CGFloat saturation;
        CGFloat brightness;
        CGFloat sampleAlpha;

        if (self.gfStyle == 0) {
            /*
             * Clear reference target: a THIN wallpaper-owned material.
             *
             * Beta2.4 gives the slider one dominant job in Clear: control the
             * local Gaussian blur.  The surrounding neutral optics barely
             * change after the first 15%, which prevents a high percentage
             * from turning Clear into a milky/brighter pseudo-LiquidGlass.
             *
             * At the 55% baseline the local blur is ~2.45 pt in dark mode and
             * ~2.22 pt in light mode.  Color still comes only from backdrop.
             */
            blurRadius = darkAppearance
                ? (4.20 * clearBlurResponse)
                : (3.80 * clearBlurResponse);

            saturation = darkAppearance
                ? (1.045 + 0.020 * clearActivation)
                : (1.030 + 0.015 * clearActivation);

            brightness = darkAppearance
                ? (0.026 + 0.008 * clearActivation)
                : (0.010 + 0.006 * clearActivation);

            sampleAlpha = darkAppearance
                ? (0.80 + 0.04 * clearActivation)
                : (0.75 + 0.04 * clearActivation);
        } else {
            /*
             * Liquid Glass: a thicker but not blackened backdrop.
             * The old ~9-10 pt dark-mode kernel smeared bright wallpaper
             * islands into a mostly black body. A slightly smaller kernel,
             * modest saturation recovery and a neutral brightness lift keep
             * the material visibly glassy without adding a hue tint.
             */
            blurRadius = darkAppearance
                ? (4.6 + 4.8 * materialResponse)
                : (4.2 + 4.2 * materialResponse);

            saturation = darkAppearance
                ? (1.070 + 0.120 * materialResponse)
                : (1.050 + 0.100 * materialResponse);

            brightness = darkAppearance
                ? (0.015 + 0.025 * materialResponse)
                : (0.006 + 0.016 * materialResponse);

            sampleAlpha = darkAppearance
                ? (0.90 + 0.08 * materialResponse)
                : (0.88 + 0.07 * materialResponse);
        }

        self.gfBackdropSampleView.alpha =
            GFClamp01(sampleAlpha);

        self.gfBackdropOverscan =
            MAX(30.0, blurRadius * 2.75 + 4.0);

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

        if (brighten && fabs(brightness) > 0.0001) {
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

            /*
             * Do not request hard edges: overscan provides real neighbouring
             * backdrop pixels, so clamping the Gaussian kernel would recreate
             * the very corner seam we are eliminating.
             */
            [filters addObject:blur];
        }

        [materialLayer
            setValue:filters
              forKey:@"filters"];

        [materialLayer
            setValue:@1.0
              forKey:@"scale"];

        /*
         * Both styles use the real wallpaper-owned backdrop. Clear simply
         * uses a much shallower/less dominant sample than Liquid Glass.
         */
        self.gfBackdropSampleView.hidden = NO;

        if (self.gfFallbackBlurView) {
            [self.gfFallbackBlurView
                removeFromSuperview];

            self.gfFallbackBlurView = nil;
        }
    } else if (self.gfStrength > 0.001) {
        self.gfBackdropSampleView.hidden = YES;

        if (!self.gfFallbackBlurView) {
            UIBlurEffectStyle effectStyle =
                (self.gfStyle == 0)
                    ? UIBlurEffectStyleSystemUltraThinMaterial
                    : UIBlurEffectStyleSystemThinMaterial;

            UIBlurEffect *effect =
                [UIBlurEffect effectWithStyle:effectStyle];

            self.gfFallbackBlurView =
                [[UIVisualEffectView alloc]
                    initWithEffect:effect];

            self.gfFallbackBlurView.userInteractionEnabled =
                NO;

            [self insertSubview:self.gfFallbackBlurView
                   aboveSubview:self.gfBackdropSampleView];
        }

        if (self.gfStyle == 0) {
            /*
             * Fallback Clear remains intentionally light. UltraThinMaterial is
             * used only when CABackdropLayer is unavailable, and at a low alpha
             * so it cannot become a milky system material card.
             */
            self.gfFallbackBlurView.alpha = clearActivation *
                (darkAppearance ? 0.30 : 0.24);
        } else {
            self.gfFallbackBlurView.alpha = darkAppearance
                ? MIN(0.48, 0.20 + 0.30 * materialResponse)
                : MIN(0.40, 0.16 + 0.25 * materialResponse);
        }
    }

    /*
     * No chromatic body tint: purple/blue/pink always comes from wallpaper.
     *
     * Apple's "Clear" appearance still has a very small neutral-white
     * transmission/specular lift.  That is optical luminance, not a hue.
     * Keep it deliberately weak so a green/orange wallpaper stays green/orange.
     * Liquid Glass keeps the body colorless; its stronger white energy lives
     * in the specular rail image instead.
     */
    self.gfTintView.backgroundColor = UIColor.whiteColor;

    if (self.gfStrength > 0.001) {
        CGFloat neutralLift = 0.0;

        if (self.gfStyle == 0) {
            /*
             * Clear body is not white and not colored. This is only a small
             * neutral transmission lift on top of the shallow wallpaper blur.
             * Above the first 15% it settles near ~4.5% white in dark
             * appearance and ~2.2% in light appearance.  The lower light-mode
             * value prevents bright
             * wallpapers from turning the folder into a pale card.
             */
            neutralLift = clearActivation *
                (darkAppearance ? 0.045 : 0.022);

            self.gfTintView.alpha =
                MIN(darkAppearance ? 0.050 : 0.026, neutralLift);
        } else {
            /*
             * Liquid Glass needs a little more neutral transmission in dark
             * mode so the thicker blur stays luminous. This is white light,
             * not a chromatic tint; wallpaper hue remains untouched.
             */
            neutralLift = darkAppearance
                ? (0.030 + 0.050 * tintResponse) * self.gfStrength
                : (0.012 + 0.025 * tintResponse) * self.gfStrength;

            self.gfTintView.alpha =
                MIN(darkAppearance ? 0.055 : 0.028, neutralLift);
        }
    } else {
        self.gfTintView.alpha = 0.0;
    }

    /*
     * Both styles keep the fixed continuous rail GEOMETRY, but Clear uses a
     * separately rendered broad/soft optical texture. Dark mode gets more
     * neutral-white definition; light mode is intentionally quieter.
     */
    if (self.gfStyle == 0) {
        self.gfOpticalLayer.opacity = clearActivation *
            (darkAppearance ? 0.80 : 0.66);
    } else {
        self.gfOpticalLayer.opacity = darkAppearance
            ? 1.0
            : 0.88;
    }

    /*
     * Beta 2.1 continuity floor. CALayer draws this border with the SAME
     * kCACornerCurveContinuous geometry that clips the panel, so it cannot
     * develop the tiny TL<->top or BR<->bottom tangent gap seen in the
     * hand-rasterized rail. It is intentionally faint; the directional
     * optical texture still provides the visible white highlight.
     */
    CGFloat continuityEdge = GFEdgeResponse(self.gfStrength);
    CGFloat continuityAlpha;

    if (self.gfStyle == 0) {
        continuityAlpha = clearActivation *
            (darkAppearance ? 0.048 : 0.032);
        self.layer.borderWidth =
            (clearActivation > 0.001) ? 0.45 : 0.0;
    } else {
        continuityAlpha = darkAppearance
            ? (0.025 + 0.040 * continuityEdge)
            : (0.018 + 0.030 * continuityEdge);
        self.layer.borderWidth =
            (self.gfStrength > 0.001) ? 0.50 : 0.0;
    }

    self.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:GFClamp01(continuityAlpha)].CGColor;

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

    CGFloat overscan =
        MAX(24.0, self.gfBackdropOverscan);

    CGRect sampleFrame =
        CGRectInset(self.bounds, -overscan, -overscan);

    self.gfBackdropSampleView.frame =
        sampleFrame;

    self.gfFallbackBlurView.frame =
        sampleFrame;

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
                self.gfStyle,
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
    /*
     * FIX6: both selectable styles own the opened panel.
     * Clear at 0% intentionally becomes a fully transparent panel, matching
     * the existing closed-folder Clear 0% semantics.
     */
    return GFEnabled && (GFStyle == 0 || GFStyle == 1);
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
                initWithStyle:GFStyle
                     strength:GFGlassStrength];

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

        if (objc_getClass("SBFolderBackgroundView")) {
            %init(GFOpenedPanelHooks);
        }
    }
}
