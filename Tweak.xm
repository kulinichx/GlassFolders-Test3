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
@property (nonatomic, strong) CAGradientLayer *gfContinuousEdgeGlow;
@property (nonatomic, strong) CAShapeLayer *gfContinuousEdgeMask;
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
                blurRadius = 5.0 + (13.0 * e);     // ~13.7 at 45%
                saturation = 1.25 + (0.70 * e);   // ~1.72 at 45%
                brightness = 0.010 + (0.030 * e);
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
                ? 0.012 + (0.040 * e)
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
            CGFloat borderAlpha = 0.17 + (0.32 * e);
            self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
            self.layer.borderColor =
                [UIColor colorWithWhite:1.0 alpha:borderAlpha].CGColor;

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
            _gfContinuousEdgeGlow = [CAGradientLayer layer];
            _gfContinuousEdgeGlow.startPoint = CGPointMake(0.00, 0.00);
            _gfContinuousEdgeGlow.endPoint = CGPointMake(1.00, 1.00);
            _gfContinuousEdgeGlow.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.82].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.54].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.07].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
            ];
            _gfContinuousEdgeGlow.locations =
                @[@0.00, @0.22, @0.48, @0.73, @1.00];
            _gfContinuousEdgeGlow.opacity = 0.18 + (0.30 * e);

            _gfContinuousEdgeMask = [CAShapeLayer layer];
            _gfContinuousEdgeMask.fillColor = UIColor.clearColor.CGColor;
            _gfContinuousEdgeMask.strokeColor = UIColor.whiteColor.CGColor;
            _gfContinuousEdgeMask.lineCap = kCALineCapRound;
            _gfContinuousEdgeMask.lineJoin = kCALineJoinRound;

            _gfContinuousEdgeGlow.mask = _gfContinuousEdgeMask;

            [self.layer addSublayer:_gfContinuousEdgeGlow];
        }
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfFallbackBlurView.frame = self.bounds;
    self.gfTintView.frame = self.bounds;
    if (self.gfContinuousEdgeGlow && self.gfContinuousEdgeMask) {
        self.gfContinuousEdgeGlow.frame = self.bounds;
        self.gfContinuousEdgeMask.frame = self.bounds;

        /*
         * A soft 2.8pt edge region gives the iOS 27-style thicker catch-light
         * without becoming a hard white border.
         *
         * The path is inset by half the stroke width so the entire highlight
         * remains inside the clipped folder shape.
         */
        CGFloat strokeWidth = 2.8;
        CGFloat pathInset = strokeWidth * 0.5 + 0.35;
        CGRect pathRect = CGRectInset(self.bounds, pathInset, pathInset);

        CGFloat pathRadius = MAX(
            0.0,
            radius - pathInset
        );

        UIBezierPath *edgePath =
            [UIBezierPath bezierPathWithRoundedRect:pathRect
                                       cornerRadius:pathRadius];

        self.gfContinuousEdgeMask.path = edgePath.CGPath;
        self.gfContinuousEdgeMask.lineWidth = strokeWidth;
    }

    CGFloat radius = self.gfPreferredRadius;

    if (radius <= 0.0 && self.superview) {
        radius = self.superview.layer.cornerRadius;
    }

    if (radius > 0.0) {
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
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
