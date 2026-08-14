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
@property (nonatomic, strong) CAShapeLayer *gfBaseOutline;
@property (nonatomic, strong) CAGradientLayer *gfWhiteRimGlow;
@property (nonatomic, strong) CAShapeLayer *gfWhiteRimMask;
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
                blurRadius = 3.2 + (9.2 * e);
                saturation = 1.08 + (0.38 * e);
                brightness = 0.003 + (0.010 * e);
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
                ? 0.003 + (0.014 * e)
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
            _gfBaseOutline = [CAShapeLayer layer];
            _gfBaseOutline.fillColor = UIColor.clearColor.CGColor;
            _gfBaseOutline.strokeColor =
                [UIColor colorWithWhite:1.0
                                  alpha:(0.038 + 0.026 * e)].CGColor;
            _gfBaseOutline.lineCap = kCALineCapRound;
            _gfBaseOutline.lineJoin = kCALineJoinRound;

            _gfWhiteRimGlow = [CAGradientLayer layer];
            _gfWhiteRimGlow.startPoint = CGPointMake(0.00, 0.00);
            _gfWhiteRimGlow.endPoint = CGPointMake(1.00, 1.00);
            _gfWhiteRimGlow.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.58].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.38].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.18].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.065].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.018].CGColor
            ];
            _gfWhiteRimGlow.locations =
                @[@0.00, @0.18, @0.44, @0.72, @1.00];
            _gfWhiteRimGlow.opacity = 0.14 + (0.18 * e);

            _gfWhiteRimMask = [CAShapeLayer layer];
            _gfWhiteRimMask.fillColor = UIColor.clearColor.CGColor;
            _gfWhiteRimMask.strokeColor = UIColor.whiteColor.CGColor;
            _gfWhiteRimMask.lineCap = kCALineCapRound;
            _gfWhiteRimMask.lineJoin = kCALineJoinRound;

            _gfWhiteRimGlow.mask = _gfWhiteRimMask;

            [self.layer addSublayer:_gfBaseOutline];
            [self.layer addSublayer:_gfWhiteRimGlow];
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
    if (self.gfBaseOutline && self.gfWhiteRimGlow && self.gfWhiteRimMask) {
        /*
         * Both layers use the SAME continuous rounded-rectangle geometry.
         * Nothing ends abruptly at 30% / 50%, so there is no artificial seam.
         *
         * The base outline is ~0.6pt and almost invisible.
         * The brighter rim is ~1.6pt but remains soft because its actual
         * brightness comes from a low-opacity white gradient.
         */
        CGFloat baseWidth = 0.60;
        CGFloat rimWidth = 1.60;
        CGFloat inset = MAX(baseWidth, rimWidth) * 0.5 + 0.28;

        CGRect pathRect = CGRectInset(self.bounds, inset, inset);
        CGFloat pathRadius = MAX(0.0, radius - inset);

        UIBezierPath *edgePath =
            [UIBezierPath bezierPathWithRoundedRect:pathRect
                                       cornerRadius:pathRadius];

        self.gfBaseOutline.frame = self.bounds;
        self.gfBaseOutline.path = edgePath.CGPath;
        self.gfBaseOutline.lineWidth = baseWidth;

        self.gfWhiteRimGlow.frame = self.bounds;
        self.gfWhiteRimMask.frame = self.bounds;
        self.gfWhiteRimMask.path = edgePath.CGPath;
        self.gfWhiteRimMask.lineWidth = rimWidth;
    }

}

@end


@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end

@interface SBFloatyFolderView : UIView
- (void)setBackgroundAlpha:(double)alpha;
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


%group GFOpenedFolderHooks

%hook SBFloatyFolderView

- (void)setBackgroundAlpha:(double)alpha {
    if (!GFEnabled || GFStyle != 1) {
        %orig(alpha);
        return;
    }

    /*
     * Keep the opened folder lightweight:
     * reuse Apple's existing large folder material, no new full-screen blur.
     */
    double e = sqrt(GFGlassStrength);
    double panelFactor = 0.24 + (0.48 * e);

    %orig(alpha * MIN(0.74, panelFactor));
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
