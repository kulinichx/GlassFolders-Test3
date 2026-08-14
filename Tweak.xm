#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

/*
 * GlassFolders 0.5.3 / Test5.3 — Backdrop Glass
 *
 * Why:
 * Test5.2's UIVisualEffectView "Light" material looked like a pale frosted card
 * on-device. This version instead uses CABackdropLayer + CAFilter when
 * available, so the wallpaper color remains visible and saturated.
 *
 * Lightweight-first:
 * - no daemon
 * - no DisplayLink
 * - no timer
 * - no gyroscope
 * - no continuously animated gradient
 * - no custom full-screen blur
 *
 * The backdrop filters are static and GPU/compositor driven.
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





@interface GFBackdropGlassView : UIView
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) UIVisualEffectView *gfFallbackBlurView;
@property (nonatomic, strong) CAGradientLayer *gfSurfaceHighlight;
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
                blurRadius = 2.8 + (7.2 * e);
                saturation = 1.04 + (0.22 * e);
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
                [blur setValue:@NO forKey:@"inputHardEdges"];
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
            /*
             * A very light static diagonal specular band.
             * This is the A/B direction discussed after Edge Glass looked flat.
             * It never animates and never reads motion sensors.
             */
            /*
             * Two static layers:
             * 1) a broader, soft internal glow (the "thick glass edge")
             * 2) a narrower specular band on top of it
             *
             * Both are static CAGradientLayer objects: no timer / no motion /
             * no continuous animation.
             */
            /*
             * Continuous rounded-edge glass highlight.
             *
             * Test5.6 used two independent strips (top + left). At the rounded
             * top-left corner those strips were inset and clipped separately,
             * creating a visible "missing highlight" gap.
             *
             * Test5.7 uses ONE gradient layer masked by ONE continuous
             * rounded-rectangle stroke. The highlight therefore flows through
             * the corner with no seam.
             *
             * Brightness falls from upper-left -> lower-right.
             * Static only: no animation / timer / motion sensor.
             */
            /*
             * Native-style local rim:
             * keep a relatively soft/wide highlight region, but only around
             * the upper-left corner and upper edge.
             *
             * This avoids the "neon outline" look seen in Test5.7.
             */
            /*
             * Native Transparent Glass:
             * a short, soft upper-left catch-light only.
             * The material remains the main visual effect.
             */
            /*
             * Apple-style transparent rim:
             *
             * 1) A very faint COMPLETE white outline keeps the glass shape
             *    coherent on every wallpaper.
             *
             * 2) A wider white rim uses a full rounded-rect stroke mask, but
             *    its gradient is strongest at the upper-left and smoothly
             *    fades toward the lower-right.
             *
             * The highlight itself is neutral white. Wallpaper color only
             * comes from the backdrop material underneath it.
             */
            /*
             * RC material highlight:
             * no stroke, no rim, no edge mask.
             *
             * This is a broad, low-contrast surface light field anchored
             * outside/near the upper-left. It should read as light on glass,
             * not as a drawn border.
             */
            _gfSurfaceHighlight = [CAGradientLayer layer];

            if (@available(iOS 12.0, *)) {
                _gfSurfaceHighlight.type = kCAGradientLayerRadial;
            }

            _gfSurfaceHighlight.startPoint = CGPointMake(0.08, 0.06);
            _gfSurfaceHighlight.endPoint = CGPointMake(0.78, 0.78);
            _gfSurfaceHighlight.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.095].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.038].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.010].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.000].CGColor
            ];
            _gfSurfaceHighlight.locations = @[@0.00, @0.36, @0.66, @1.00];
            _gfSurfaceHighlight.opacity = 0.72 + (0.16 * e);

            [self.layer addSublayer:_gfSurfaceHighlight];
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
    if (self.gfSurfaceHighlight) {
        /*
         * Slight overscan makes the radial field fade naturally before it
         * reaches the hard clip boundary.
         */
        self.gfSurfaceHighlight.frame =
            CGRectInset(self.bounds, -6.0, -6.0);
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
@property (nonatomic, strong) CAGradientLayer *gfSurfaceHighlight;
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
            CGFloat blurRadius = 7.5 + (13.0 * e);
            CGFloat saturation = 1.00 + (0.12 * e);
            CGFloat brightness = 0.002 + (0.006 * e);

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
                [blur setValue:@NO forKey:@"inputHardEdges"];
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
        CGFloat tintAlpha = 0.022 + (0.024 * e);

        if (_gfStrength > 0.001 && tintAlpha > 0.001) {
            _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
            _gfTintView.userInteractionEnabled = NO;
            _gfTintView.backgroundColor = UIColor.whiteColor;
            _gfTintView.alpha = tintAlpha;
            [self addSubview:_gfTintView];
        }

        if (_gfStrength > 0.001) {
            /*
             * Same Apple-style white edge language as the closed folder,
             * slightly wider because this is a much larger surface.
             */
            /*
             * Large surface highlight:
             * weaker than the closed icon because the frosted material itself
             * already establishes depth.
             *
             * Again: no line, no border, no rim mask.
             */
            _gfSurfaceHighlight = [CAGradientLayer layer];

            if (@available(iOS 12.0, *)) {
                _gfSurfaceHighlight.type = kCAGradientLayerRadial;
            }

            _gfSurfaceHighlight.startPoint = CGPointMake(0.08, 0.05);
            _gfSurfaceHighlight.endPoint = CGPointMake(0.70, 0.72);
            _gfSurfaceHighlight.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.070].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.026].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.006].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.000].CGColor
            ];
            _gfSurfaceHighlight.locations = @[@0.00, @0.34, @0.66, @1.00];
            _gfSurfaceHighlight.opacity = 0.62 + (0.14 * e);

            [self.layer addSublayer:_gfSurfaceHighlight];
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

    if (self.gfSurfaceHighlight) {
        self.gfSurfaceHighlight.frame =
            CGRectInset(self.bounds, -10.0, -10.0);
    }
}

@end


static UIView *GFOpenedFolderBackgroundReferenceView(UIView *container) {
    UIView *best = nil;
    CGFloat bestArea = 0.0;

    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[GFOpenedFolderGlassView class]]) {
            continue;
        }

        NSString *name = NSStringFromClass(subview.class);
        BOOL likelyBackground =
            [name containsString:@"Background"] ||
            [name containsString:@"Material"] ||
            [name containsString:@"Backdrop"];

        if (!likelyBackground) {
            continue;
        }

        CGFloat area =
            CGRectGetWidth(subview.bounds) * CGRectGetHeight(subview.bounds);

        if (area > bestArea) {
            bestArea = area;
            best = subview;
        }
    }

    return best;
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

    if (!glass) {
        glass =
            [[GFOpenedFolderGlassView alloc] initWithStrength:GFGlassStrength];

        [self insertSubview:glass atIndex:0];
        GFSetOpenedGlassView(self, glass);
    }

    UIView *reference = GFOpenedFolderBackgroundReferenceView(self);

    CGRect targetFrame = self.bounds;
    CGFloat targetRadius = self.layer.cornerRadius;

    if (reference) {
        targetFrame = reference.frame;

        if (reference.layer.cornerRadius > 0.0) {
            targetRadius = reference.layer.cornerRadius;
        }
    }

    glass.frame = targetFrame;
    [glass setPreferredRadius:targetRadius];

    /*
     * SpringBoard may reorder subviews during the transition.
     * Keep the glass behind folder icons/page controls.
     */
    [self sendSubviewToBack:glass];
}

- (void)setBackgroundAlpha:(double)alpha {
    if (!GFEnabled || GFStyle != 1) {
        %orig(alpha);
        return;
    }

    GFOpenedFolderGlassView *glass = GFGetOpenedGlassView(self);

    if (!glass) {
        glass =
            [[GFOpenedFolderGlassView alloc] initWithStrength:GFGlassStrength];

        [self insertSubview:glass atIndex:0];
        GFSetOpenedGlassView(self, glass);
    }

    /*
     * Apple's existing background-alpha animation drives our glass.
     * No custom transition animator or continuous renderer is added.
     */
    glass.alpha = MIN(1.0, MAX(0.0, alpha));

    /*
     * Hide only Apple's original opened-folder panel material.
     * The surrounding wallpaper blur/dim stays stock.
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
