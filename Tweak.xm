#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

/*
 * GlassFolders 0.5.2 / Test5.2 — Edge Glass
 *
 * Design goal:
 * - Clear stays extremely light.
 * - Liquid Glass uses Apple's existing material ideas:
 *   background color passes through, subtle depth, stronger top/upper-left
 *   catch-light, very weak remaining edge.
 *
 * Performance goal:
 * - no daemon
 * - no DisplayLink
 * - no timer
 * - no continuous custom animation
 * - no full-screen custom blur
 * - no shadow rendering
 * - preferences loaded once per SpringBoard launch
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


@interface GFGlassFolderPlateView : UIView
@property (nonatomic, strong) UIVisualEffectView *gfBlurView;
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, strong) CAGradientLayer *gfTopCatchLight;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) NSInteger gfStyle;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
- (instancetype)initWithStyle:(NSInteger)style
                     strength:(CGFloat)strength
               preferredRadius:(CGFloat)radius;
@end

@implementation GFGlassFolderPlateView

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

        CGFloat blurAlpha = 0.0;
        CGFloat tintAlpha = 0.0;
        CGFloat edgeAlpha = 0.0;
        CGFloat topCatchAlpha = 0.0;
        UIBlurEffectStyle blurStyle = UIBlurEffectStyleSystemUltraThinMaterial;

        if (_gfStyle == 1 && _gfStrength > 0.001) {
            /*
             * Medium values become visibly useful sooner without needing
             * 80-100%. This keeps 40-55% in the main "Liquid Glass" zone.
             */
            CGFloat e = sqrt(_gfStrength);

            blurStyle = UIBlurEffectStyleSystemUltraThinMaterialLight;

            blurAlpha = MIN(0.93, 0.52 + (0.55 * e));
            tintAlpha = 0.022 + (0.090 * e);

            /*
             * The full border is deliberately weak.
             * The visible "glass catch" comes from the upper edge instead.
             */
            edgeAlpha = 0.08 + (0.19 * e);
            topCatchAlpha = 0.20 + (0.34 * e);
        } else if (_gfStyle == 0) {
            /*
             * Clear mode remains close to the stable Test4 behavior.
             * At 0%, no blur view is allocated.
             */
            blurAlpha = 0.70 * _gfStrength;
            tintAlpha = 0.035 * _gfStrength;
        }

        if (blurAlpha > 0.005) {
            UIBlurEffect *effect = [UIBlurEffect effectWithStyle:blurStyle];

            _gfBlurView = [[UIVisualEffectView alloc] initWithEffect:effect];
            _gfBlurView.alpha = blurAlpha;
            _gfBlurView.userInteractionEnabled = NO;
            [self addSubview:_gfBlurView];
        }

        if (tintAlpha > 0.001) {
            _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
            _gfTintView.userInteractionEnabled = NO;
            _gfTintView.backgroundColor = UIColor.whiteColor;
            _gfTintView.alpha = tintAlpha;
            [self addSubview:_gfTintView];
        }

        if (_gfStyle == 1 && edgeAlpha > 0.001) {
            CGFloat scale = UIScreen.mainScreen.scale;

            self.layer.borderWidth = 1.0 / scale;
            self.layer.borderColor =
                [UIColor colorWithWhite:1.0 alpha:edgeAlpha].CGColor;

            /*
             * One tiny static gradient only along the top edge.
             * It is NOT a diagonal full-surface highlight.
             *
             * Left/top is strongest, fading toward the right.
             * No animation, no redraw loop, no motion sensor.
             */
            _gfTopCatchLight = [CAGradientLayer layer];
            _gfTopCatchLight.startPoint = CGPointMake(0.0, 0.5);
            _gfTopCatchLight.endPoint = CGPointMake(1.0, 0.5);
            _gfTopCatchLight.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.95].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.52].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor
            ];
            _gfTopCatchLight.locations = @[@0.00, @0.24, @0.66, @1.00];
            _gfTopCatchLight.opacity = topCatchAlpha;

            [self.layer addSublayer:_gfTopCatchLight];
        }
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfBlurView.frame = self.bounds;
    self.gfTintView.frame = self.bounds;

    CGFloat radius = self.gfPreferredRadius;

    if (radius <= 0.0 && self.superview) {
        radius = self.superview.layer.cornerRadius;
    }

    if (radius > 0.0) {
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }

    if (self.gfTopCatchLight) {
        CGFloat scale = UIScreen.mainScreen.scale;
        CGFloat lineHeight = MAX(1.0 / scale, 0.45);

        /*
         * Keep the catch-light just inside the rounded top edge.
         * Insets prevent it from looking like a hard rectangular rule.
         */
        CGFloat horizontalInset = MAX(4.0, radius * 0.20);

        self.gfTopCatchLight.frame = CGRectMake(
            horizontalInset,
            0.55 / scale,
            MAX(0.0, CGRectGetWidth(self.bounds) - (horizontalInset * 2.0)),
            lineHeight
        );

        self.gfTopCatchLight.cornerRadius = lineHeight * 0.5;
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

    CGFloat originalRadius = backgroundView ? backgroundView.layer.cornerRadius : 0.0;

    GFGlassFolderPlateView *plate =
        [[GFGlassFolderPlateView alloc] initWithStyle:GFStyle
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

    if (GFGlassStrength <= 0.001) {
        %orig(0.0);
        return;
    }

    /*
     * Larger surface = slightly "thicker" material.
     * Still reuses Apple's own opened-folder material.
     *
     * No additional full-screen blur is created.
     * Multiplication preserves Apple's transition curve.
     */
    double e = sqrt(GFGlassStrength);
    double panelFactor = 0.26 + (0.53 * e);

    %orig(alpha * MIN(0.80, panelFactor));
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
