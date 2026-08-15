#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>

/*
 * GlassFolders 1.0.0 — commercial release candidate
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

static CFStringRef const GFPreferencesDomain = CFSTR("com.kulinich.glassfolders");

static BOOL GFEnabled = YES;  // Folder glass only; legacy preference key: Enabled
static NSInteger GFStyle = 0;          // 0 Clear, 1 Liquid Glass
static CGFloat GFClearStrength = 0.0;        // 0.0 ... 1.0, Clear blur authority
static CGFloat GFLiquidGlassStrength = 0.0;  // 0.0 ... 1.0, Liquid composite authority
static CGFloat GFGlassStrength = 0.0;        // active style strength for existing rendering paths

// App Library remains intentionally independent from normal folders.
static BOOL GFAppLibraryGlassEnabled = NO;

// Legacy Beta 3.6–4.4 value, retained for compatibility:
// 0 = Clear, 1 = Liquid Glass
static NSInteger GFAppLibraryStyle = 0;

// Beta 4.5 public selector:
// 0 = Follow Folder, 1 = Clear, 2 = Liquid Glass
static NSInteger GFAppLibraryStyleMode = 0;

// Clear: 0 Apple Bright, 1 Balanced, 2 Soft
static NSInteger GFAppLibraryClearPreset = 0;

// Liquid Glass: 0 Crystal, 1 Balanced, 2 Deep
static NSInteger GFAppLibraryLiquidPreset = 0;

/*
 * Kept only for source/backward compatibility with Beta 3.2–3.5 installs.
 * Beta 3.6 no longer exposes or uses an App Library percentage slider.
 */
static CGFloat GFAppLibraryGlassStrength = 0.55;

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

    /*
     * Beta 2.8 keeps the split-control migration contract: Clear and Liquid Glass keep independent strength
     * values. Existing installs inherit the legacy GlassStrength value the
     * first time these new keys are absent, so upgrading does not silently
     * change the user's current appearance.
     */
    CGFloat legacyStrength = GFReadPercent(CFSTR("GlassStrength"), 55.0);
    GFClearStrength = GFReadPercent(
        CFSTR("ClearStrength"),
        legacyStrength * 100.0
    );
    GFLiquidGlassStrength = GFReadPercent(
        CFSTR("LiquidGlassStrength"),
        legacyStrength * 100.0
    );

    GFAppLibraryGlassEnabled =
        GFReadBool(CFSTR("AppLibraryGlassEnabled"), NO);

    GFAppLibraryStyle =
        GFReadInteger(CFSTR("AppLibraryStyle"), 0);

    GFAppLibraryStyleMode =
        GFReadInteger(CFSTR("AppLibraryStyleMode"), 0);

    /*
     * Beta 4.6 final UI:
     * App Library preset pickers are intentionally hidden.
     * Lock the internal recipes to the accepted visual baselines:
     * Clear = Apple Bright, Liquid Glass = Crystal.
     */
    GFAppLibraryClearPreset = 0;
    GFAppLibraryLiquidPreset = 0;

    /*
     * Read the legacy key only so old preferences remain harmless.
     * It no longer controls the Beta 3.6 resource-library material.
     */
    GFAppLibraryGlassStrength =
        GFReadPercent(CFSTR("AppLibraryGlassStrength"), 55.0);

    if (GFAppLibraryStyle < 0 || GFAppLibraryStyle > 1) {
        GFAppLibraryStyle = 0;
    }

    if (GFAppLibraryStyleMode < 0 ||
        GFAppLibraryStyleMode > 2) {
        GFAppLibraryStyleMode = 0;
    }

    if (GFAppLibraryClearPreset < 0 ||
        GFAppLibraryClearPreset > 2) {
        GFAppLibraryClearPreset = 0;
    }

    if (GFAppLibraryLiquidPreset < 0 ||
        GFAppLibraryLiquidPreset > 2) {
        GFAppLibraryLiquidPreset = 0;
    }

    if (GFStyle < 0 || GFStyle > 1) {
        GFStyle = 0;
    }

    GFGlassStrength =
        (GFStyle == 0) ? GFClearStrength : GFLiquidGlassStrength;
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


static BOOL GFUsesDarkAppearance(UIView *view);


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
    /*
     * Closed Clear keeps the accepted Beta2.4 response unchanged. Do not let
     * opened-panel calibration silently move the closed-folder baseline.
     */
    return pow(GFClamp01(strength), 0.90);
}

/*
 * Opened folders already sit over SpringBoard's full-screen blur, therefore
 * small 2–8 pt local kernels are visually swallowed by the host blur. Beta2.8
 * keeps ClearStrength as an intentionally high-authority blur control while
 * keeping the material itself colorless and thin:
 *   0%   ->  0.0 pt
 *   10%  -> ~2.8 pt
 *   25%  -> ~8.1 pt
 *   50%  -> ~18.0 pt
 *   55%  -> ~20.1 pt
 *   75%  -> ~28.7 pt
 *   100% -> 40.0 pt
 *
 * The 1.15 exponent keeps the very bottom usable but deliberately opens the
 * low/middle range sooner. This is important because SpringBoard has already
 * blurred the full-screen background before the folder-local material samples
 * it; a timid local kernel is visually swallowed. Closed Clear retains its
 * separately locked response.
 */
static inline CGFloat GFClearOpenedBlurResponse(CGFloat strength) {
    return pow(GFClamp01(strength), 1.15);
}


/*
 * Clear strength no longer owns the basic "is this transparent/clean?" state.
 *
 * The Clear mode itself establishes the high-transmission baseline, including
 * at 0%. The slider then adds structure: local blur, chroma separation and
 * optical-edge definition. This prevents low Clear values from falling back
 * to the host's dull/grey opened-folder blur.
 *
 * 0%   -> 0.00 structure
 * 25%  -> 0.156 structure
 * 50%  -> 0.50 structure
 * 75%  -> 0.844 structure
 * 100% -> 1.00 structure
 */
static inline CGFloat GFClearStructureResponse(CGFloat strength) {
    CGFloat s = GFClamp01(strength);
    return s * s * (3.0 - 2.0 * s);
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





static char kGFInternalAppLibraryPodVisualKey;
static char kGFAppLibraryOverlayAssociationKey;
static char kGFAppLibraryOriginalAlphaKey;
static char kGFAppLibraryRootMarkerKey;

// Beta 3.4: App Library search field shares the App Library glass setting.
static char kGFAppLibrarySearchOverlayAssociationKey;
static char kGFAppLibrarySearchOriginalBackgroundColorKey;
static char kGFAppLibrarySearchNativeBackgroundAlphaKey;

static BOOL GFIsInternalAppLibraryPodVisual(UIView *view) {
    NSNumber *marker = objc_getAssociatedObject(
        view,
        &kGFInternalAppLibraryPodVisualKey
    );
    return marker.boolValue;
}

static void GFMarkInternalAppLibraryPodVisual(UIView *view) {
    if (!view) return;

    objc_setAssociatedObject(
        view,
        &kGFInternalAppLibraryPodVisualKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
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

    /*
     * This object is a private copy used only inside our normal folder
     * material. Mark it before UIKit can lay it out so the Beta 3.2 real
     * App Library hook will always ignore it.
     */
    GFMarkInternalAppLibraryPodVisual(podView);

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
    BOOL darkAppearance = GFUsesDarkAppearance(podView);

    /*
     * Beta 3.1:
     * Light-mode closed folders were reading as bright pink/white cards.
     * Keep the accepted dark blend, but in light appearance let the wallpaper
     * dominate and use the native pod only as a restrained material cue.
     */
    podView.alpha = darkAppearance
        ? MIN(0.54, 0.24 + 0.30 * materialResponse)
        : MIN(0.34, 0.12 + 0.18 * materialResponse);

    return podView;
}


#pragma mark - Beta 3.6 App Library Fixed Material Recipes

typedef struct {
    CGFloat blur;
    CGFloat saturation;
    CGFloat brightness;
    CGFloat tintAlpha;
    CGFloat borderWidth;
    CGFloat borderAlpha;
    CGFloat nativePodAlpha;
    CGFloat nativeSearchAlpha;
} GFAppLibraryMaterialRecipe;


static NSInteger GFResolvedAppLibraryStyle(void) {
    /*
     * Beta 4.5:
     * 0 Follow Folder -> use normal folder GFStyle
     * 1 Clear         -> force Clear
     * 2 Liquid Glass  -> force Liquid Glass
     *
     * GFStyle already uses 0 = Clear, 1 = Liquid Glass.
     */
    switch (GFAppLibraryStyleMode) {
        case 1:
            return 0;

        case 2:
            return 1;

        case 0:
        default:
            return (GFStyle == 1) ? 1 : 0;
    }
}


static GFAppLibraryMaterialRecipe GFAppLibraryRecipe(
    BOOL searchVariant,
    BOOL dark
) {
    GFAppLibraryMaterialRecipe r = {
        8.0, 1.10, 0.010, 0.020,
        0.34, 0.14, 0.22, 0.08
    };

    NSInteger resolvedStyle = GFResolvedAppLibraryStyle();

    if (resolvedStyle == 0) {
        /*
         * CLEAR
         *
         * The reference is intentionally bright and luminous. Unlike normal
         * Clear folder strength, these are fixed design presets so the whole
         * App Library remains visually coherent.
         */
        switch (GFAppLibraryClearPreset) {
            case 1: // Balanced
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        9.3, 1.13, 0.032, 0.038,
                        0.34, 0.145, 0.22, 0.065
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        9.2, 1.13, 0.038, 0.052,
                        0.34, 0.155, 0.25, 0.07
                    };
                }
                break;

            case 2: // Soft
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        11.6, 1.09, 0.026, 0.049,
                        0.32, 0.130, 0.25, 0.075
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        12.6, 1.08, 0.030, 0.068,
                        0.32, 0.140, 0.28, 0.08
                    };
                }
                break;

            case 0:
            default: // Apple Bright
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        9.9, 1.15, 0.043, 0.047,
                        0.36, 0.160, 0.21, 0.058
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        10.8, 1.15, 0.058, 0.076,
                        0.36, 0.175, 0.24, 0.06
                    };
                }
                break;
        }

        /*
         * Search is an interactive control, so lift it only a tiny amount.
         * Beta 3.5 was deliberately much brighter and looked disconnected.
         */
        /*
         * Beta 4.4:
         * searchVariant intentionally does NOT alter the material recipe.
         * Search is the same Clear material as a category card.
         */
    } else {
        /*
         * LIQUID GLASS
         *
         * Lower blur and body tint. Wallpaper transmission stays strong and
         * the object is identified mainly by the thin optical edge/native
         * shading, matching the transparent Liquid Glass reference.
         */
        switch (GFAppLibraryLiquidPreset) {
            case 1: // Balanced
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        7.4, 1.21, 0.019, 0.015,
                        0.35, 0.155, 0.15, 0.052
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        7.2, 1.23, 0.019, 0.014,
                        0.34, 0.155, 0.17, 0.052
                    };
                }
                break;

            case 2: // Deep
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        9.2, 1.14, 0.010, 0.020,
                        0.37, 0.160, 0.21, 0.070
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        9.0, 1.15, 0.009, 0.020,
                        0.35, 0.150, 0.22, 0.070
                    };
                }
                break;

            case 0:
            default: // Crystal
                if (dark) {
                    r = (GFAppLibraryMaterialRecipe){
                        5.6, 1.27, 0.024, 0.0095,
                        0.37, 0.180, 0.11, 0.036
                    };
                } else {
                    r = (GFAppLibraryMaterialRecipe){
                        5.4, 1.30, 0.027, 0.0085,
                        0.36, 0.175, 0.12, 0.032
                    };
                }
                break;
        }

        /*
         * Beta 4.4:
         * searchVariant intentionally does NOT alter the material recipe.
         * Search is the same Liquid Glass material as a category card.
         */
    }

    return r;
}


#pragma mark - Beta 3.2 App Library Glass

@interface GFAppLibraryGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) CAGradientLayer *gfUpperLeftBloomLayer;
@property (nonatomic, strong) CAShapeLayer *gfPartialRimLayer;
@property (nonatomic, strong) CAGradientLayer *gfLowerLeftGlintLayer;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) BOOL gfSearchVariant;
- (instancetype)initWithStrength:(CGFloat)strength;
- (void)setPreferredRadius:(CGFloat)radius;
- (void)gfRefreshMaterial;
@end

@implementation GFAppLibraryGlassView

+ (Class)layerClass {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    return backdropClass ?: [CALayer class];
}

- (instancetype)initWithStrength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStrength = GFClamp01(strength);
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
        _gfTintView.userInteractionEnabled = NO;
        _gfTintView.backgroundColor = UIColor.whiteColor;
        [self addSubview:_gfTintView];

        /*
         * Beta 4.2 starts from the proven Beta 3.6 visual base.
         * These are intentionally LOCAL optical cues:
         *
         * - broad upper-left luminosity bloom
         * - a thin rim only around the upper corners/top
         * - a tiny lower-left reflection
         *
         * No horizontal white cap. No full second outline.
         */
        _gfUpperLeftBloomLayer =
            [CAGradientLayer layer];
        _gfUpperLeftBloomLayer.startPoint =
            CGPointMake(0.0, 0.0);
        _gfUpperLeftBloomLayer.endPoint =
            CGPointMake(1.0, 1.0);
        _gfUpperLeftBloomLayer.cornerCurve =
            kCACornerCurveContinuous;
        [self.layer addSublayer:_gfUpperLeftBloomLayer];

        _gfPartialRimLayer =
            [CAShapeLayer layer];
        _gfPartialRimLayer.fillColor =
            UIColor.clearColor.CGColor;
        _gfPartialRimLayer.lineCap =
            kCALineCapRound;
        _gfPartialRimLayer.lineJoin =
            kCALineJoinRound;
        [self.layer addSublayer:_gfPartialRimLayer];

        _gfLowerLeftGlintLayer =
            [CAGradientLayer layer];
        _gfLowerLeftGlintLayer.startPoint =
            CGPointMake(0.0, 0.5);
        _gfLowerLeftGlintLayer.endPoint =
            CGPointMake(1.0, 0.5);
        _gfLowerLeftGlintLayer.cornerCurve =
            kCACornerCurveContinuous;
        [self.layer addSublayer:_gfLowerLeftGlintLayer];

        [self gfRefreshMaterial];
    }

    return self;
}

- (void)setPreferredRadius:(CGFloat)radius {
    _gfPreferredRadius = MAX(0.0, radius);
    self.layer.cornerRadius = _gfPreferredRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    [self setNeedsLayout];
}

- (void)gfRefreshMaterial {
    BOOL dark = GFUsesDarkAppearance(self);

    BOOL isBackdropLayer =
        [NSStringFromClass(self.layer.class) containsString:@"Backdrop"];

    GFAppLibraryMaterialRecipe recipe =
        GFAppLibraryRecipe(
            self.gfSearchVariant,
            dark
        );

    CGFloat blurRadius = recipe.blur;
    CGFloat saturation = recipe.saturation;
    CGFloat brightness = recipe.brightness;

    if (isBackdropLayer) {
        id saturate = GFCreateCAFilter(@"colorSaturate");
        id brighten = GFCreateCAFilter(@"colorBrightness");
        id blur = GFCreateCAFilter(@"gaussianBlur");

        NSMutableArray *filters = [NSMutableArray array];

        if (saturate) {
            [saturate setValue:@(saturation) forKey:@"inputAmount"];
            [filters addObject:saturate];
        }

        if (brighten) {
            [brighten setValue:@(brightness) forKey:@"inputAmount"];
            [filters addObject:brighten];
        }

        if (blur) {
            [blur setValue:@(blurRadius) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [blur setValue:@YES forKey:@"inputHardEdges"];
            [filters addObject:blur];
        }

        [self.layer setValue:filters forKey:@"filters"];
        [self.layer setValue:@1.0 forKey:@"scale"];
    }

    self.gfTintView.alpha =
        recipe.tintAlpha;

    self.layer.borderWidth =
        recipe.borderWidth;

    self.layer.borderColor =
        [UIColor colorWithWhite:1.0
                          alpha:recipe.borderAlpha]
            .CGColor;

    BOOL liquid =
        (GFResolvedAppLibraryStyle() == 1);

    CGFloat bloomAlpha = 0.0;
    CGFloat rimAlpha = 0.0;
    CGFloat glintAlpha = 0.0;

    if (liquid) {
        switch (GFAppLibraryLiquidPreset) {
            case 1: // Balanced
                bloomAlpha = dark ? 0.108 : 0.105;
                rimAlpha = dark ? 0.132 : 0.130;
                glintAlpha = dark ? 0.048 : 0.050;
                break;

            case 2: // Deep
                bloomAlpha = dark ? 0.082 : 0.080;
                rimAlpha = dark ? 0.112 : 0.110;
                glintAlpha = dark ? 0.038 : 0.040;
                break;

            case 0:
            default: // Crystal
                bloomAlpha = dark ? 0.132 : 0.135;
                rimAlpha = dark ? 0.156 : 0.155;
                glintAlpha = dark ? 0.058 : 0.060;
                break;
        }
    } else {
        /*
         * Clear keeps its Beta3.6 luminous/frosted body. Only very subtle
         * corner light is added so Clear does not turn into Liquid Glass.
         */
        switch (GFAppLibraryClearPreset) {
            case 1:
                bloomAlpha = dark ? 0.050 : 0.050;
                rimAlpha = dark ? 0.056 : 0.055;
                glintAlpha = dark ? 0.021 : 0.018;
                break;

            case 2:
                bloomAlpha = dark ? 0.038 : 0.040;
                rimAlpha = dark ? 0.044 : 0.045;
                glintAlpha = dark ? 0.017 : 0.014;
                break;

            case 0:
            default:
                bloomAlpha = dark ? 0.057 : 0.060;
                rimAlpha = dark ? 0.063 : 0.065;
                glintAlpha = dark ? 0.024 : 0.020;
                break;
        }
    }

    /*
     * Beta 4.4:
     * search and category cards use the same optical alpha values.
     * No search-specific bloom/rim/glint suppression or amplification.
     */

    self.gfUpperLeftBloomLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0
                              alpha:bloomAlpha * 0.82].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:bloomAlpha * 0.48].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:bloomAlpha * 0.18].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:0.0].CGColor
    ];

    self.gfUpperLeftBloomLayer.locations =
        @[@0.00, @0.28, @0.58, @1.00];

    self.gfPartialRimLayer.strokeColor =
        [UIColor colorWithWhite:1.0
                          alpha:rimAlpha]
            .CGColor;

    self.gfPartialRimLayer.lineWidth =
        liquid ? 0.68 : 0.52;

    self.gfLowerLeftGlintLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0
                              alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:glintAlpha].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:glintAlpha * 0.34].CGColor,
        (id)[UIColor colorWithWhite:1.0
                              alpha:0.0].CGColor
    ];

    self.gfLowerLeftGlintLayer.locations =
        @[@0.00, @0.34, @0.60, @1.00];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfTintView.frame =
        self.bounds;

    CGRect bounds =
        self.bounds;

    CGFloat radius =
        self.gfPreferredRadius;

    if (radius <= 0.0) {
        radius =
            MIN(
                CGRectGetWidth(bounds),
                CGRectGetHeight(bounds)
            ) * 0.18;
    }

    BOOL liquid =
        (GFResolvedAppLibraryStyle() == 1);

    /*
     * Broad corner luminosity. It occupies AREA, not an edge strip.
     */
    CGFloat bloomWidth =
        CGRectGetWidth(bounds) *
        (self.gfSearchVariant
            ? (liquid ? 0.52 : 0.46)
            : (liquid ? 0.52 : 0.46));

    CGFloat bloomHeight =
        CGRectGetHeight(bounds) *
        (self.gfSearchVariant
            ? (liquid ? 0.48 : 0.42)
            : (liquid ? 0.48 : 0.42));

    self.gfUpperLeftBloomLayer.frame =
        CGRectMake(
            -radius * 0.10,
            -radius * 0.08,
            MAX(1.0, bloomWidth),
            MAX(1.0, bloomHeight)
        );

    self.gfUpperLeftBloomLayer.cornerRadius =
        MIN(
            radius,
            MIN(bloomWidth, bloomHeight) * 0.44
        );

    /*
     * A single partial rim follows ONLY the upper corners/top.
     * The existing Beta3.6 base border remains the only full silhouette.
     */
    CGRect rimRect =
        CGRectInset(bounds, 0.80, 0.80);

    CGFloat rimRadius =
        MIN(
            MAX(0.0, radius - 0.80),
            MIN(
                CGRectGetWidth(rimRect),
                CGRectGetHeight(rimRect)
            ) * 0.50
        );

    UIBezierPath *rimPath =
        [UIBezierPath bezierPath];

    CGFloat minX = CGRectGetMinX(rimRect);
    CGFloat maxX = CGRectGetMaxX(rimRect);
    CGFloat minY = CGRectGetMinY(rimRect);

    [rimPath moveToPoint:
        CGPointMake(
            minX,
            minY + rimRadius * 1.15
        )];

    [rimPath addArcWithCenter:
        CGPointMake(
            minX + rimRadius,
            minY + rimRadius
        )
        radius:rimRadius
        startAngle:(CGFloat)M_PI
        endAngle:(CGFloat)(M_PI * 1.5)
        clockwise:YES];

    [rimPath addLineToPoint:
        CGPointMake(
            maxX - rimRadius,
            minY
        )];

    [rimPath addArcWithCenter:
        CGPointMake(
            maxX - rimRadius,
            minY + rimRadius
        )
        radius:rimRadius
        startAngle:(CGFloat)(M_PI * 1.5)
        endAngle:0.0
        clockwise:YES];

    self.gfPartialRimLayer.frame =
        bounds;
    self.gfPartialRimLayer.path =
        rimPath.CGPath;

    /*
     * Very small lower-left reflection.
     */
    CGFloat glintWidth =
        MIN(
            CGRectGetWidth(bounds) * 0.18,
            MAX(
                28.0,
                radius * 1.12
            )
        );

    CGFloat glintHeight =
        MIN(
            3.6,
            MAX(
                2.0,
                radius * 0.095
            )
        );

    self.gfLowerLeftGlintLayer.frame =
        CGRectMake(
            MAX(4.0, radius * 0.30),
            MAX(
                0.0,
                CGRectGetHeight(bounds) -
                glintHeight -
                1.0
            ),
            glintWidth,
            glintHeight
        );

    self.gfLowerLeftGlintLayer.cornerRadius =
        glintHeight * 0.5;
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    [super traitCollectionDidChange:previousTraitCollection];
    [self gfRefreshMaterial];
}

@end


static GFAppLibraryGlassView *GFAppLibraryOverlayForPod(UIView *pod) {
    return (GFAppLibraryGlassView *)
        objc_getAssociatedObject(
            pod,
            &kGFAppLibraryOverlayAssociationKey
        );
}

static void GFSetAppLibraryOverlayForPod(
    UIView *pod,
    GFAppLibraryGlassView *overlay
) {
    objc_setAssociatedObject(
        pod,
        &kGFAppLibraryOverlayAssociationKey,
        overlay,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void GFRestoreNativeAppLibraryPod(UIView *pod) {
    GFAppLibraryGlassView *overlay =
        GFAppLibraryOverlayForPod(pod);

    if (overlay) {
        [overlay removeFromSuperview];
        GFSetAppLibraryOverlayForPod(pod, nil);
    }

    NSNumber *originalAlpha =
        objc_getAssociatedObject(
            pod,
            &kGFAppLibraryOriginalAlphaKey
        );

    if (originalAlpha) {
        pod.alpha = originalAlpha.doubleValue;

        objc_setAssociatedObject(
            pod,
            &kGFAppLibraryOriginalAlphaKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

static void GFUpdateRealAppLibraryPod(UIView *pod) {
    if (!pod || GFIsInternalAppLibraryPodVisual(pod)) {
        return;
    }

    BOOL enabled =
        GFAppLibraryGlassEnabled;

    if (!enabled) {
        GFRestoreNativeAppLibraryPod(pod);
        return;
    }

    UIView *host = pod.superview;
    if (!host) {
        return;
    }

    NSNumber *originalAlpha =
        objc_getAssociatedObject(
            pod,
            &kGFAppLibraryOriginalAlphaKey
        );

    if (!originalAlpha) {
        objc_setAssociatedObject(
            pod,
            &kGFAppLibraryOriginalAlphaKey,
            @(pod.alpha),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    GFAppLibraryGlassView *overlay =
        GFAppLibraryOverlayForPod(pod);

    if (!overlay) {
        overlay =
            [[GFAppLibraryGlassView alloc]
                initWithStrength:1.0];

        GFSetAppLibraryOverlayForPod(
            pod,
            overlay
        );
    }

    if (overlay.superview != host) {
        [overlay removeFromSuperview];
        [host insertSubview:overlay
               belowSubview:pod];
    } else {
        [host insertSubview:overlay
               belowSubview:pod];
    }

    overlay.bounds = pod.bounds;
    overlay.center = pod.center;
    overlay.transform = pod.transform;
    overlay.hidden = pod.hidden;

    CGFloat radius = pod.layer.cornerRadius;
    if (radius <= 0.0) {
        radius =
            MIN(pod.bounds.size.width,
                pod.bounds.size.height) * 0.18;
    }

    [overlay setPreferredRadius:radius];

    /*
     * Keep just enough of Apple's native background to preserve its visual
     * identity, while the new sibling overlay supplies the real wallpaper
     * transmission. This view is background-only; app icons are not children
     * of SBHLibraryCategoryPodBackgroundView.
     */
    BOOL dark = GFUsesDarkAppearance(pod);

    GFAppLibraryMaterialRecipe recipe =
        GFAppLibraryRecipe(
            NO,
            dark
        );

    pod.alpha =
        recipe.nativePodAlpha;
}



#pragma mark - App Library Search Glass (1.0 FIX8 iPad geometry)

/*
 * Beta 3.4 required the candidate itself to look like a Search class.
 * On the tested SpringBoard the visible pill is a private wrapper, so the
 * category cards were hit but the search pill was never selected.
 *
 * Beta 3.5 resolves the search UI in two stages:
 *
 * 1) locate a real UITextField / UISearchTextField / UISearchBar descendant,
 *    then walk UP to the wide rounded pill container;
 * 2) if that UIKit input is hidden behind private wrappers, fall back to the
 *    unique wide + shallow + rounded view near the top of SBLibraryViewController.
 */

static BOOL GFAppLibrarySearchGeometryMatches(
    UIView *view,
    UIView *root
) {
    if (!view ||
        !root ||
        view == root ||
        view.hidden ||
        view.alpha <= 0.01) {
        return NO;
    }

    CGRect rect =
        [view convertRect:view.bounds
                   toView:root];

    CGFloat rootWidth =
        CGRectGetWidth(root.bounds);
    CGFloat rootHeight =
        CGRectGetHeight(root.bounds);

    CGFloat width =
        CGRectGetWidth(rect);
    CGFloat height =
        CGRectGetHeight(rect);

    if (rootWidth <= 1.0 ||
        rootHeight <= 1.0 ||
        width <= 1.0 ||
        height <= 1.0) {
        return NO;
    }

    /*
     * iPhone and iPad use noticeably different App Library search widths.
     *
     * iPhone:
     *   search is normally a wide page-level pill.
     *
     * iPad:
     *   search is a centered, medium-width pill above the 4-column category
     *   grid. Requiring >= 52% of the page width rejects the real iPad pill.
     *
     * Keep the proven iPhone thresholds untouched and add a dedicated iPad
     * geometry branch.
     */
    UIUserInterfaceIdiom idiom =
        root.traitCollection.userInterfaceIdiom;

    BOOL iPadLayout =
        idiom == UIUserInterfaceIdiomPad ||
        rootWidth >= 700.0;

    BOOL wideEnough =
        iPadLayout
            ? (
                width >= rootWidth * 0.28 &&
                width <= rootWidth * 0.72
            )
            : (
                width >= rootWidth * 0.52 &&
                width <= rootWidth * 0.98
            );

    BOOL shallowEnough =
        height >= 34.0 &&
        height <= 104.0;

    BOOL nearTop =
        CGRectGetMinY(rect) >= -12.0 &&
        CGRectGetMidY(rect) <=
            rootHeight * (iPadLayout ? 0.32 : 0.28);

    BOOL pillAspect =
        width / MAX(height, 1.0) >=
            (iPadLayout ? 3.6 : 3.2);

    /*
     * The iPad search pill is intentionally centered. This extra constraint
     * lets us accept its narrower width without accidentally selecting a
     * shallow category/header view elsewhere in the hierarchy.
     */
    BOOL centeredEnough = YES;

    if (iPadLayout) {
        CGFloat centerDelta =
            fabs(
                CGRectGetMidX(rect) -
                rootWidth * 0.5
            );

        centeredEnough =
            centerDelta <= rootWidth * 0.18;
    }

    return wideEnough &&
           shallowEnough &&
           nearTop &&
           pillAspect &&
           centeredEnough;
}


static BOOL GFIsUIKitSearchInputView(
    UIView *view
) {
    if (!view) return NO;

    if ([view isKindOfClass:[UISearchBar class]] ||
        [view isKindOfClass:[UITextField class]]) {
        return YES;
    }

    Class searchTextFieldClass =
        NSClassFromString(@"UISearchTextField");

    if (searchTextFieldClass &&
        [view isKindOfClass:searchTextFieldClass]) {
        return YES;
    }

    return NO;
}


static BOOL GFClassNameLooksSearchRelated(
    UIView *view
) {
    if (!view) return NO;

    NSString *name =
        NSStringFromClass(view.class);

    NSArray<NSString *> *tokens = @[
        @"Search",
        @"Spotlight",
        @"Query"
    ];

    for (NSString *token in tokens) {
        if ([name rangeOfString:token
                        options:NSCaseInsensitiveSearch].location
                != NSNotFound) {
            return YES;
        }
    }

    return NO;
}


static void GFFindBestAppLibrarySearchInput(
    UIView *view,
    UIView *root,
    UIView **bestView,
    CGFloat *bestScore
) {
    if (!view ||
        !root ||
        !bestView ||
        !bestScore) {
        return;
    }

    if (view != root &&
        !view.hidden &&
        view.alpha > 0.01) {

        CGFloat score = -CGFLOAT_MAX;

        if (GFIsUIKitSearchInputView(view)) {
            score = 200.0;
        } else if (GFClassNameLooksSearchRelated(view)) {
            score = 100.0;
        }

        if (score > -CGFLOAT_MAX / 2.0) {
            CGRect rect =
                [view convertRect:view.bounds
                           toView:root];

            CGFloat rootHeight =
                MAX(
                    CGRectGetHeight(root.bounds),
                    1.0
                );

            /*
             * Prefer actual visible search inputs near the top.
             * Width is intentionally NOT required here; the real text field
             * can be narrower than its outer glass pill.
             */
            UIUserInterfaceIdiom idiom =
                root.traitCollection.userInterfaceIdiom;

            BOOL iPadLayout =
                idiom == UIUserInterfaceIdiomPad ||
                CGRectGetWidth(root.bounds) >= 700.0;

            if (CGRectGetMidY(rect) <=
                    rootHeight *
                        (iPadLayout ? 0.36 : 0.30) &&
                CGRectGetHeight(rect) >= 20.0 &&
                CGRectGetHeight(rect) <= 110.0) {

                if ([view isKindOfClass:[UITextField class]]) {
                    score += 60.0;
                }

                if ([view isKindOfClass:[UISearchBar class]]) {
                    score += 30.0;
                }

                score +=
                    MIN(
                        25.0,
                        CGRectGetWidth(rect) * 0.04
                    );

                if (score > *bestScore) {
                    *bestScore = score;
                    *bestView = view;
                }
            }
        }
    }

    for (UIView *child in [view.subviews copy]) {
        GFFindBestAppLibrarySearchInput(
            child,
            root,
            bestView,
            bestScore
        );
    }
}


static CGFloat GFAppLibrarySearchContainerScore(
    UIView *view,
    UIView *root
) {
    if (!GFAppLibrarySearchGeometryMatches(
            view,
            root
        )) {
        return -CGFLOAT_MAX;
    }

    if ([view isKindOfClass:[UILabel class]] ||
        [view isKindOfClass:[UIImageView class]] ||
        [view isKindOfClass:[UIButton class]] ||
        [view isKindOfClass:[UIWindow class]]) {
        return -CGFLOAT_MAX;
    }

    CGRect rect =
        [view convertRect:view.bounds
                   toView:root];

    CGFloat rootWidth =
        MAX(
            CGRectGetWidth(root.bounds),
            1.0
        );

    CGFloat rootHeight =
        MAX(
            CGRectGetHeight(root.bounds),
            1.0
        );

    CGFloat width =
        CGRectGetWidth(rect);

    CGFloat height =
        MAX(
            CGRectGetHeight(rect),
            1.0
        );

    CGFloat radius =
        view.layer.cornerRadius;

    UIUserInterfaceIdiom idiom =
        root.traitCollection.userInterfaceIdiom;

    BOOL iPadLayout =
        idiom == UIUserInterfaceIdiomPad ||
        rootWidth >= 700.0;

    CGFloat score = 0.0;

    /*
     * Width remains useful, but on iPad the actual search pill is narrower
     * than the page. Add a center-position score so the correct iPad pill
     * still wins without weakening the iPhone fallback.
     */
    score +=
        70.0 *
        MIN(
            1.0,
            width / rootWidth
        );

    if (iPadLayout) {
        CGFloat normalizedCenterDelta =
            fabs(
                CGRectGetMidX(rect) -
                rootWidth * 0.5
            ) /
            rootWidth;

        score +=
            28.0 *
            (
                1.0 -
                MIN(
                    1.0,
                    normalizedCenterDelta / 0.18
                )
            );
    }

    score -=
        24.0 *
        (CGRectGetMidY(rect) /
         rootHeight);

    CGFloat expectedHeight =
        iPadLayout ? 58.0 : 56.0;
    score -=
        MIN(
            20.0,
            fabs(height - expectedHeight) * 0.25
        );

    if (radius >= height * 0.30) {
        score += 24.0;
    } else if (radius >= height * 0.18) {
        score += 12.0;
    }

    if (view.clipsToBounds ||
        view.layer.masksToBounds) {
        score += 6.0;
    }

    if (GFClassNameLooksSearchRelated(view)) {
        score += 35.0;
    }

    NSString *name =
        NSStringFromClass(view.class);

    NSArray<NSString *> *materialTokens = @[
        @"Platter",
        @"Pill",
        @"Material",
        @"Backdrop",
        @"Background"
    ];

    for (NSString *token in materialTokens) {
        if ([name rangeOfString:token
                        options:NSCaseInsensitiveSearch].location
                != NSNotFound) {
            score += 8.0;
            break;
        }
    }

    return score;
}


static UIView *GFResolveAppLibrarySearchContainerFromInput(
    UIView *input,
    UIView *root
) {
    if (!input || !root) {
        return nil;
    }

    UIView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;

    UIView *node = input;

    /*
     * Start at the input and climb only a few wrappers. This is the key
     * Beta 3.5 fix: the visible pill can be a private parent whose own class
     * name contains no "Search" token at all.
     */
    for (NSInteger depth = 0;
         node &&
         node != root &&
         depth < 9;
         depth++) {

        CGFloat score =
            GFAppLibrarySearchContainerScore(
                node,
                root
            );

        if (score > bestScore) {
            bestScore = score;
            best = node;
        }

        node = node.superview;
    }

    return best;
}


static void GFFindGeometrySearchContainer(
    UIView *view,
    UIView *root,
    UIView **bestView,
    CGFloat *bestScore
) {
    if (!view ||
        !root ||
        !bestView ||
        !bestScore) {
        return;
    }

    if (view != root) {
        CGFloat score =
            GFAppLibrarySearchContainerScore(
                view,
                root
            );

        if (score > *bestScore) {
            *bestScore = score;
            *bestView = view;
        }
    }

    for (UIView *child in [view.subviews copy]) {
        GFFindGeometrySearchContainer(
            child,
            root,
            bestView,
            bestScore
        );
    }
}


static UIView *GFFindAppLibrarySearchContainer(
    UIView *root
) {
    if (!root) return nil;

    UIView *input = nil;
    CGFloat inputScore = -CGFLOAT_MAX;

    GFFindBestAppLibrarySearchInput(
        root,
        root,
        &input,
        &inputScore
    );

    UIView *fromInput =
        GFResolveAppLibrarySearchContainerFromInput(
            input,
            root
        );

    if (fromInput) {
        return fromInput;
    }

    /*
     * Last-resort geometry fallback.
     *
     * This intentionally does NOT require Search/UISearch* class names.
     * It runs only inside the already-confirmed SBLibraryViewController root.
     */
    UIView *geometryCandidate = nil;
    CGFloat geometryScore = -CGFLOAT_MAX;

    GFFindGeometrySearchContainer(
        root,
        root,
        &geometryCandidate,
        &geometryScore
    );

    /*
     * Reject weak geometry matches rather than touching a random header.
     */
    if (geometryScore < 42.0) {
        return nil;
    }

    return geometryCandidate;
}


static BOOL GFLooksLikeNativeSearchBackgroundView(
    UIView *view
) {
    if (!view ||
        [view isKindOfClass:[GFAppLibraryGlassView class]]) {
        return NO;
    }

    NSString *name =
        NSStringFromClass(view.class);

    NSArray<NSString *> *tokens = @[
        @"Background",
        @"Backdrop",
        @"Material",
        @"Platter",
        @"Pill"
    ];

    for (NSString *token in tokens) {
        if ([name rangeOfString:token
                        options:NSCaseInsensitiveSearch].location
                != NSNotFound) {
            return YES;
        }
    }

    return NO;
}


static void GFSetNativeSearchBackgroundsDimmed(
    UIView *view,
    BOOL dimmed
) {
    if (!view) return;

    for (UIView *child in [view.subviews copy]) {
        if ([child isKindOfClass:[GFAppLibraryGlassView class]]) {
            continue;
        }

        if (GFLooksLikeNativeSearchBackgroundView(child)) {
            NSNumber *original =
                objc_getAssociatedObject(
                    child,
                    &kGFAppLibrarySearchNativeBackgroundAlphaKey
                );

            if (dimmed) {
                if (!original) {
                    objc_setAssociatedObject(
                        child,
                        &kGFAppLibrarySearchNativeBackgroundAlphaKey,
                        @(child.alpha),
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }

                /*
                 * Keep a trace of Apple's original search material so its
                 * internal shading still participates, but remove the dark
                 * opaque slab that was visible in Beta 3.3.
                 */
                GFAppLibraryMaterialRecipe searchRecipe =
                    GFAppLibraryRecipe(
                        YES,
                        GFUsesDarkAppearance(view)
                    );

                /*
                 * Beta 4.4: keep native search material participation aligned
                 * with the category-card material, not independently reduced.
                 */
                child.alpha =
                    searchRecipe.nativePodAlpha;
            } else if (original) {
                child.alpha = original.doubleValue;

                objc_setAssociatedObject(
                    child,
                    &kGFAppLibrarySearchNativeBackgroundAlphaKey,
                    nil,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC
                );
            }
        }

        GFSetNativeSearchBackgroundsDimmed(
            child,
            dimmed
        );
    }
}


static GFAppLibraryGlassView *GFAppLibrarySearchOverlay(
    UIView *searchView
) {
    return (GFAppLibraryGlassView *)
        objc_getAssociatedObject(
            searchView,
            &kGFAppLibrarySearchOverlayAssociationKey
        );
}


static void GFRestoreAppLibrarySearchView(
    UIView *searchView
) {
    if (!searchView) return;

    GFAppLibraryGlassView *overlay =
        GFAppLibrarySearchOverlay(searchView);

    if (overlay) {
        [overlay removeFromSuperview];

        objc_setAssociatedObject(
            searchView,
            &kGFAppLibrarySearchOverlayAssociationKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    id originalBackground =
        objc_getAssociatedObject(
            searchView,
            &kGFAppLibrarySearchOriginalBackgroundColorKey
        );

    if (originalBackground) {
        searchView.backgroundColor =
            (originalBackground == [NSNull null])
                ? nil
                : (UIColor *)originalBackground;

        objc_setAssociatedObject(
            searchView,
            &kGFAppLibrarySearchOriginalBackgroundColorKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    GFSetNativeSearchBackgroundsDimmed(
        searchView,
        NO
    );
}


static void GFUpdateAppLibrarySearchView(
    UIView *root
) {
    if (!root) return;

    UIView *candidate =
        GFFindAppLibrarySearchContainer(
            root
        );

    if (!candidate) {
        return;
    }

    BOOL enabled =
        GFAppLibraryGlassEnabled;

    if (!enabled) {
        GFRestoreAppLibrarySearchView(candidate);
        return;
    }

    id savedBackground =
        objc_getAssociatedObject(
            candidate,
            &kGFAppLibrarySearchOriginalBackgroundColorKey
        );

    if (!savedBackground) {
        UIColor *originalColor =
            candidate.backgroundColor;

        objc_setAssociatedObject(
            candidate,
            &kGFAppLibrarySearchOriginalBackgroundColorKey,
            originalColor ?: (id)[NSNull null],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    candidate.backgroundColor =
        UIColor.clearColor;

    GFSetNativeSearchBackgroundsDimmed(
        candidate,
        YES
    );

    GFAppLibraryGlassView *overlay =
        GFAppLibrarySearchOverlay(candidate);

    if (!overlay) {
        overlay =
            [[GFAppLibraryGlassView alloc]
                initWithStrength:1.0];

        overlay.gfSearchVariant = YES;
        overlay.gfStrength = 1.0;
        [overlay gfRefreshMaterial];

        objc_setAssociatedObject(
            candidate,
            &kGFAppLibrarySearchOverlayAssociationKey,
            overlay,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        [candidate insertSubview:overlay
                         atIndex:0];
    } else {
        overlay.gfSearchVariant = YES;
        overlay.gfStrength = 1.0;
        [overlay gfRefreshMaterial];

        if (overlay.superview != candidate) {
            [overlay removeFromSuperview];
            [candidate insertSubview:overlay
                             atIndex:0];
        } else {
            [candidate sendSubviewToBack:overlay];
        }
    }

    overlay.frame = candidate.bounds;
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    CGFloat radius =
        candidate.layer.cornerRadius;

    if (radius <= 0.0) {
        radius =
            CGRectGetHeight(candidate.bounds) * 0.50;
    }

    [overlay setPreferredRadius:radius];
}


/*
 * Normal folder icons and App Library mini-clusters both pass through
 * SBFolderIconImageView. The old all-or-nothing hook therefore painted our
 * desktop folder glass onto the mini-clusters inside App Library.
 *
 * Beta 3.2 explicitly separates that hierarchy: if a folder icon is under
 * any SpringBoard Library/CategoryPod container, leave Apple's original
 * background untouched. On stock iOS this is the transparent mini-folder
 * presentation the user expects.
 */
static BOOL GFViewIsInsideAppLibrary(UIView *view) {
    UIResponder *node = view;

    for (NSInteger depth = 0;
         node && depth < 28;
         depth++) {

        if ([node isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)node;

            NSNumber *rootMarker =
                objc_getAssociatedObject(
                    v,
                    &kGFAppLibraryRootMarkerKey
                );

            if (rootMarker.boolValue) {
                return YES;
            }
        }

        NSString *className =
            NSStringFromClass(node.class);

        BOOL looksLikeLibrary =
            [className containsString:@"SBHLibrary"] ||
            [className containsString:@"SBLibrary"] ||
            [className containsString:@"LibraryCategory"] ||
            [className containsString:@"CategoryPod"];

        if (looksLikeLibrary) {
            return YES;
        }

        if ([node isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)node;

            if (v.superview) {
                node = v.superview;
                continue;
            }
        }

        node = node.nextResponder;
    }

    return NO;
}


/*
 * Beta 3.3 no longer depends on the category-background class already being
 * hookable during tweak construction.
 *
 * SBLibraryViewController is the page-level App Library controller. Every
 * time the page lays out, walk only that controller's hierarchy and locate
 * category background candidates there.
 */
static BOOL GFLooksLikeRealAppLibraryCategoryBackground(UIView *view) {
    if (!view || GFIsInternalAppLibraryPodVisual(view)) {
        return NO;
    }

    Class exactClass =
        NSClassFromString(
            @"SBHLibraryCategoryPodBackgroundView"
        );

    if (exactClass &&
        [view isKindOfClass:exactClass]) {
        return YES;
    }

    NSString *name =
        NSStringFromClass(view.class);

    BOOL categoryBackgroundName =
        ([name containsString:@"Library"] &&
         [name containsString:@"Category"] &&
         [name containsString:@"Background"]);

    BOOL podBackgroundName =
        ([name containsString:@"CategoryPod"] &&
         [name containsString:@"Background"]);

    return categoryBackgroundName ||
           podBackgroundName;
}


static void GFRefreshAppLibraryDescendants(UIView *view) {
    if (!view) return;

    if (GFLooksLikeRealAppLibraryCategoryBackground(view)) {
        GFUpdateRealAppLibraryPod(view);
    }

    NSArray<UIView *> *children =
        [view.subviews copy];

    for (UIView *child in children) {
        GFRefreshAppLibraryDescendants(child);
    }
}


static void GFRefreshAppLibraryController(
    UIViewController *controller
) {
    if (!controller.isViewLoaded) {
        return;
    }

    UIView *root = controller.view;
    if (!root) {
        return;
    }

    objc_setAssociatedObject(
        root,
        &kGFAppLibraryRootMarkerKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    GFRefreshAppLibraryDescendants(root);

    /*
     * Beta 3.4: the top App Library search pill shares the same independent
     * App Library glass switch/strength as the category cards.
     */
    GFUpdateAppLibrarySearchView(root);
}


@interface SBHLibraryCategoryPodBackgroundView : UIView
@end

@interface SBLibraryViewController : UIViewController
@end

%group GFAppLibraryControllerHooks

%hook SBLibraryViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    GFRefreshAppLibraryController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    GFRefreshAppLibraryController(self);

    /*
     * Some category pods are recycled/attached immediately after the first
     * appearance callback. One next-runloop refresh catches that path without
     * polling or globally hooking UIView.
     */
    __weak UIViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongSelf = weakSelf;
        if (strongSelf) {
            GFRefreshAppLibraryController(strongSelf);
        }
    });

    /*
     * The search wrapper can be attached one layout phase later than category
     * pods. A single short delayed refresh is cheap and avoids a global hook.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.18 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            UIViewController *strongSelf = weakSelf;
            if (strongSelf) {
                GFRefreshAppLibraryController(strongSelf);
            }
        }
    );
}

- (void)viewDidLayoutSubviews {
    %orig;
    GFRefreshAppLibraryController(self);
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    %orig(previousTraitCollection);
    GFRefreshAppLibraryController(self);
}

%end

%end


%group GFAppLibraryHooks

%hook SBHLibraryCategoryPodBackgroundView

- (void)didMoveToSuperview {
    %orig;
    GFUpdateRealAppLibraryPod(self);
}

- (void)didMoveToWindow {
    %orig;
    GFUpdateRealAppLibraryPod(self);
}

- (void)layoutSubviews {
    %orig;
    GFUpdateRealAppLibraryPod(self);
}

- (void)traitCollectionDidChange:
    (UITraitCollection *)previousTraitCollection {

    %orig(previousTraitCollection);

    GFAppLibraryGlassView *overlay =
        GFAppLibraryOverlayForPod(self);

    if (overlay) {
        [overlay gfRefreshMaterial];
    }

    GFUpdateRealAppLibraryPod(self);
}

%end

%end


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
        CGFloat clearStructure = GFClearStructureResponse(_gfStrength);
        BOOL clearStyle = (_gfStyle == 0);
        BOOL darkAppearance = GFUsesDarkAppearance(self);
        BOOL materialRequested = clearStyle || (_gfStrength > 0.001);

        if (materialRequested && isBackdropLayer) {
            /*
             * Preserve wallpaper color instead of whitening it.
             * At 45–55%, blur stays moderate while saturation is boosted.
             */
            CGFloat blurRadius;
            CGFloat saturation;
            CGFloat brightness;

            if (_gfStyle == 1) {
                /*
                 * Liquid Glass closed-folder body: keep Apple's App Library
                 * pod identity, but let the wallpaper own most of the color.
                 * The native pod is now a thin material cue rather than the
                 * main opaque body.
                 */
                blurRadius = darkAppearance
                    ? (4.2 + 5.8 * materialResponse)
                    : (3.6 + 4.4 * materialResponse);

                saturation = darkAppearance
                    ? (1.10 + 0.18 * materialResponse)
                    : (1.06 + 0.10 * materialResponse);

                brightness = darkAppearance
                    ? (0.010 + 0.018 * materialResponse)
                    : (0.001 + 0.006 * materialResponse);
            } else {
                /*
                 * Clear starts clean even at 0%.  The slider keeps blur as its
                 * largest change, while color separation and a very small
                 * neutral luminance lift grow with structure.  Do not use the
                 * slider as the gate for Clear transparency.
                 */
                blurRadius = 8.40 * clearBlurResponse;
                saturation = 1.105 + (0.070 * clearStructure);
                brightness = 0.014 + (0.008 * clearStructure);
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

            if (blur && blurRadius > 0.001) {
                [blur setValue:@(blurRadius) forKey:@"inputRadius"];
                [blur setValue:@YES forKey:@"inputNormalizeEdges"];
                [blur setValue:@YES forKey:@"inputHardEdges"];
                [filters addObject:blur];
            }

            if (filters.count > 0) {
                [self.layer setValue:filters forKey:@"filters"];
                [self.layer setValue:@1.0 forKey:@"scale"];
            }
        } else if (materialRequested) {
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
                (_gfStyle == 1)
                    ? (darkAppearance
                        ? MIN(0.66, 0.38 + 0.28 * materialResponse)
                        : MIN(0.38, 0.18 + 0.20 * materialResponse))
                    : (0.20 + 0.08 * clearStructure);

            [self addSubview:_gfFallbackBlurView];
        }

        /*
         * Neutral optical transmission only. No hue is introduced here:
         * wallpaper/backdrop remains the sole color source. Liquid Glass
         * restores the proven Beta1.8 light-body lift that produced the
         * user's accepted closed-folder reference.
         */
        CGFloat tintAlpha = 0.0;

        if (_gfStyle == 0) {
            tintAlpha = 0.012 + (0.006 * clearStructure);
        } else if (_gfStrength > 0.001) {
            tintAlpha = darkAppearance
                ? (0.010 + 0.028 * tintResponse)
                : (0.002 + 0.010 * tintResponse);
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
            _gfOpticalLightingLayer.opacity = darkAppearance ? 1.0 : 0.82;

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
        (style != 0 && strength <= 0.001)) {
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
        @"P24-%@-%@-%zux%zu-r%.2f-s%ld",
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
    CGFloat clearStructure = clearStyle
        ? GFClearStructureResponse(strength)
        : 1.0;

    /*
     * Clear always has a visible thin-glass edge, including at 0%.  Strength
     * now adds edge definition instead of deciding whether the edge exists.
     * The base remains softer than Liquid Glass.
     */
    CGFloat e = clearStyle
        ? (0.50 + 0.20 * clearStructure)
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
            : (6.2 + 1.8 * e)) * renderScale;

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
            : (0.010 + 0.005 * e);
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
                ? (0.24 + 0.22 * clearStructure)
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
             * Beta 2.8 — locked symmetric continuous tangent rails.
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
            CGFloat topRightTransitionGain;
            CGFloat bottomLeftTransitionGain;

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

                topRightTransitionGain = darkAppearance
                    ? (0.0013 + 0.0050 * edgeDrive)
                    : (0.0010 + 0.0038 * edgeDrive);

                bottomLeftTransitionGain = topRightTransitionGain;
            } else {
                primaryFilamentGain = darkAppearance
                    ? (0.036 + 0.300 * edgeDrive)
                    : (0.046 + 0.360 * edgeDrive);

                primaryCoreGain = darkAppearance
                    ? (0.014 + 0.090 * edgeDrive)
                    : (0.016 + 0.100 * edgeDrive);

                primaryShoulderGain = darkAppearance
                    ? (0.008 + 0.035 * edgeDrive)
                    : (0.010 + 0.040 * edgeDrive);

                secondaryFilamentGain = darkAppearance
                    ? (0.024 + 0.220 * edgeDrive)
                    : (0.016 + 0.150 * edgeDrive);

                secondaryCoreGain = darkAppearance
                    ? (0.009 + 0.064 * edgeDrive)
                    : (0.006 + 0.045 * edgeDrive);

                secondaryShoulderGain = darkAppearance
                    ? (0.005 + 0.023 * edgeDrive)
                    : (0.004 + 0.016 * edgeDrive);

                sideMiddleGain = darkAppearance
                    ? (0.0018 + 0.010 * edgeDrive)
                    : (0.0008 + 0.0035 * edgeDrive);

                /*
                 * Apple-reference opened Liquid Glass: the top/upper-left
                 * filament stays dominant, while the lower-left corner gets
                 * a compact specular glint instead of a uniformly bright
                 * perimeter.  The upper-right remains only a transition cue.
                 */
                topRightTransitionGain = darkAppearance
                    ? (0.0025 + 0.010 * edgeDrive)
                    : (0.0010 + 0.004 * edgeDrive);

                bottomLeftTransitionGain = darkAppearance
                    ? (0.008 + 0.045 * edgeDrive)
                    : (0.018 + 0.095 * edgeDrive);
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

                filament * topRightTransition *
                    topRightTransitionGain +

                filament * bottomLeftTransition *
                    bottomLeftTransitionGain +

                /* A small soft bloom under the lower-left Liquid glint. */
                (clearStyle ? 0.0 :
                    (core * bottomLeftTransition *
                        bottomLeftTransitionGain * 0.36 +
                     shoulder * bottomLeftTransition *
                        bottomLeftTransitionGain * 0.14)) +

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
                    : (0.220 + 0.320 * edgeDrive);
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
        GFClearOpenedBlurResponse(self.gfStrength);

    CGFloat clearStructure =
        GFClearStructureResponse(self.gfStrength);

    BOOL clearStyle =
        (self.gfStyle == 0);

    BOOL materialRequested =
        clearStyle || (self.gfStrength > 0.001);

    CALayer *materialLayer =
        self.gfBackdropSampleView.layer;

    BOOL isBackdropLayer =
        [NSStringFromClass(materialLayer.class)
            containsString:@"Backdrop"];

    if (materialRequested &&
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
             * Beta3.1 keeps the wide local Gaussian curve unchanged, but no
             * longer gates Clear's clean/transmitted look behind the strength
             * slider. 0% already uses the Clear optical baseline; strength adds
             * blur, chroma separation and edge structure.
             *
             * At the 55% baseline the local blur is ~20.1 pt in both appearances;
             * at 100% it reaches 40 pt.  Clear is intentionally NOT constrained
             * to a numerically smaller radius than Liquid Glass: the two styles
             * are separated by tint/lift/specular behavior, not by blur radius
             * alone.  Color still comes only from the wallpaper backdrop.
             */
            /*
             * Clear strength is now calibrated against the *already blurred*
             * SpringBoard background. Use the same blur curve in light/dark
             * appearance so the slider has one predictable meaning; only the
             * neutral optical compensation differs by appearance.
             */
            /*
             * Light Clear is calibrated against Apple's brighter Clear
             * references. SpringBoard already applies a full-screen blur, so
             * another 40 pt locally over-averages wallpaper chroma and reads
             * as grey/frosted. Keep the accepted dark-mode ceiling unchanged,
             * but let light Clear top out at 28 pt so color shapes still pass
             * through the folder body.
             */
            blurRadius = darkAppearance
                ? (40.0 * clearBlurResponse)
                : (28.0 * clearBlurResponse);

            /*
             * High-transmission Clear contract:
             *
             * - luminance starts high instead of ramping from a dull host blur;
             * - light mode restores wallpaper chroma more aggressively;
             * - brightness is supplied by the backdrop filter, not a milky
             *   white overlay;
             * - sample opacity stays essentially full so the real wallpaper
             *   remains the source of the glass body color.
             */
            saturation = darkAppearance
                ? (1.080 + 0.065 * clearStructure)
                : (1.120 + 0.120 * clearStructure);

            brightness = darkAppearance
                ? (0.048 + 0.006 * clearStructure)
                : (0.075 + 0.035 * clearStructure);

            sampleAlpha = darkAppearance
                ? (0.992 + 0.006 * clearStructure)
                : (0.995 + 0.005 * clearStructure);
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
                : (2.6 + 2.8 * materialResponse);

            saturation = darkAppearance
                ? (1.070 + 0.120 * materialResponse)
                : (1.110 + 0.220 * materialResponse);

            brightness = darkAppearance
                ? (0.015 + 0.025 * materialResponse)
                : (0.026 + 0.030 * materialResponse);

            sampleAlpha = darkAppearance
                ? (0.90 + 0.08 * materialResponse)
                : (0.975 + 0.025 * materialResponse);
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

        if (blur && blurRadius > 0.001) {
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
    } else if (materialRequested) {
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
            self.gfFallbackBlurView.alpha = darkAppearance
                ? (0.20 + 0.10 * clearStructure)
                : (0.12 + 0.06 * clearStructure);
        } else {
            self.gfFallbackBlurView.alpha = darkAppearance
                ? MIN(0.48, 0.20 + 0.30 * materialResponse)
                : MIN(0.28, 0.10 + 0.18 * materialResponse);
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

    if (self.gfStyle == 0) {
        /*
         * Clear transmission is a mode baseline, not a strength ramp.  Start
         * close to the previous high-strength white-light compensation and
         * only add a few tenths of a percent as structure rises.
         */
        CGFloat neutralLift = darkAppearance
            ? (0.050 + 0.004 * clearStructure)
            : (0.022 + 0.006 * clearStructure);

        self.gfTintView.alpha =
            MIN(darkAppearance ? 0.054 : 0.028, neutralLift);
    } else if (self.gfStrength > 0.001) {
        /*
         * Liquid Glass keeps the Beta2.8 composite-strength behavior.
         */
        CGFloat neutralLift = darkAppearance
            ? (0.030 + 0.050 * tintResponse) * self.gfStrength
            : (0.002 + 0.006 * tintResponse) * self.gfStrength;

        self.gfTintView.alpha =
            MIN(darkAppearance ? 0.055 : 0.008, neutralLift);
    } else {
        self.gfTintView.alpha = 0.0;
    }

    /*
     * Both styles keep the fixed continuous rail GEOMETRY, but Clear uses a
     * separately rendered broad/soft optical texture. Dark mode gets more
     * neutral-white definition; light mode is intentionally quieter.
     */
    if (self.gfStyle == 0) {
        self.gfOpticalLayer.opacity = darkAppearance
            ? (0.72 + 0.14 * clearStructure)
            : (0.70 + 0.20 * clearStructure);
    } else {
        self.gfOpticalLayer.opacity = darkAppearance
            ? 1.0
            : 1.0;
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
        continuityAlpha = darkAppearance
            ? (0.030 + 0.022 * clearStructure)
            : (0.032 + 0.026 * clearStructure);
        self.layer.borderWidth = 0.45;
    } else {
        continuityAlpha = darkAppearance
            ? (0.025 + 0.040 * continuityEdge)
            : (0.006 + 0.010 * continuityEdge);
        self.layer.borderWidth =
            (self.gfStrength > 0.001)
                ? (darkAppearance ? 0.42 : 0.34)
                : 0.0;
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
     * Both selectable styles own the opened panel. Clear at 0% still uses the
     * high-transmission Clear baseline; only its added blur/structure is zero.
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
     * App Library mini-folders/clusters must keep Apple's native transparent
     * presentation. Do not install Clear/Liquid Glass inside a category pod.
     */
    if (GFViewIsInsideAppLibrary(self)) {
        %orig(backgroundView);
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

        /*
         * App Library page hook is the authoritative Beta 3.3 link.
         * SBLibraryViewController belongs to SpringBoard and is present on
         * systems that provide App Library.
         */
        if (objc_getClass("SBLibraryViewController")) {
            %init(GFAppLibraryControllerHooks);
        }

        /*
         * Exact category-background hook remains only as a fast path when
         * that private SpringBoardHome class is already loaded here.
         * Controller traversal above does not depend on this succeeding.
         */
        if (objc_getClass("SBHLibraryCategoryPodBackgroundView")) {
            %init(GFAppLibraryHooks);
        }
    }
}
