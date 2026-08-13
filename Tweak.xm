#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

/*
 * GlassFolders 0.5 / Test5
 *
 * Lightweight-first design:
 * - no daemon
 * - no display link
 * - no continuous custom animation
 * - no live preference observer
 * - no full-screen custom blur
 *
 * Preferences are loaded once when SpringBoard starts.
 * Changes intentionally require one Respring.
 *
 * Style 0: Clear
 * Style 1: Liquid Glass
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
 * Home Screen folder plate owned entirely by the tweak.
 *
 * This keeps the stable Test3.1 architecture: Apple's original material
 * background is not retained. Therefore SpringBoard page reuse cannot restore
 * Apple's folder blur behind our back.
 *
 * Memory/GPU optimization:
 * at strength ~0 we do not create a UIVisualEffectView at all.
 */
@interface GFGlassFolderPlateView : UIView
@property (nonatomic, strong) UIVisualEffectView *gfBlurView;
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, assign) CGFloat gfStrength;
@property (nonatomic, assign) NSInteger gfStyle;
- (instancetype)initWithStyle:(NSInteger)style strength:(CGFloat)strength;
@end

@implementation GFGlassFolderPlateView

- (instancetype)initWithStyle:(NSInteger)style strength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        _gfStyle = style;
        _gfStrength = MIN(1.0, MAX(0.0, strength));

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;

        CGFloat blurAlpha = 0.0;
        CGFloat tintAlpha = 0.0;
        CGFloat borderAlpha = 0.0;

        if (_gfStyle == 1) {
            // Liquid Glass: still deliberately subtle.
            blurAlpha = 0.85 * _gfStrength;
            tintAlpha = 0.065 * _gfStrength;
            borderAlpha = 0.32 * _gfStrength;
        } else {
            // Clear: same visual family as 0.4, no decorative edge.
            blurAlpha = 0.70 * _gfStrength;
            tintAlpha = 0.035 * _gfStrength;
        }

        /*
         * Avoid allocating a blur view for fully transparent folders.
         * This is the common Clear=0% case and is as light as Test3.1.
         */
        if (blurAlpha > 0.005) {
            UIBlurEffect *effect =
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];

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

        if (borderAlpha > 0.001) {
            self.layer.borderWidth = 0.75 / UIScreen.mainScreen.scale;
            self.layer.borderColor =
                [UIColor colorWithWhite:1.0 alpha:borderAlpha].CGColor;
        }
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.gfBlurView) {
        self.gfBlurView.frame = self.bounds;
    }

    if (self.gfTintView) {
        self.gfTintView.frame = self.bounds;
    }

    /*
     * Inherit SpringBoard's own folder geometry where available.
     * We do not invent a new folder size or shape.
     */
    CGFloat radius = self.superview.layer.cornerRadius;
    if (radius > 0.0) {
        self.layer.cornerRadius = radius;
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

    GFGlassFolderPlateView *plate =
        [[GFGlassFolderPlateView alloc] initWithStyle:GFStyle
                                             strength:GFGlassStrength];

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
     * Lightweight Liquid Glass opened-folder look:
     * reuse Apple's existing folder material and only scale its alpha.
     *
     * No additional blur view is created here.
     * No display link / continuous renderer is used.
     *
     * 0% strength -> airy ~18% panel
     * 100% strength -> stronger ~58% panel
     */
    double panelFactor = 0.18 + (0.40 * GFGlassStrength);

    /*
     * Multiplication preserves Apple's own open/close animation curve.
     */
    %orig(alpha * panelFactor);
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
