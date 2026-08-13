#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

/*
 * GlassFolders 0.4 / Test4
 *
 * Based on the stable Test3.1 approach:
 * replace SpringBoard's folder-icon background view instead of merely
 * changing the system material view's alpha.
 *
 * Test4 adds ONLY:
 * - master enable/disable preference
 * - Home Screen glass strength (0-100)
 *
 * It still does NOT touch opened folders, wallpaper backdrop, layout,
 * titles, gestures, Dock, launchd, or jailbreak filesystem paths.
 */

static CFStringRef const GFPreferencesDomain = CFSTR("com.local.glassfolders");

static BOOL GFEnabled = YES;
static CGFloat GFGlassStrength = 0.0; // 0.0 ... 1.0

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
    GFGlassStrength = GFReadPercent(CFSTR("GlassStrength"), 0.0);
}


/*
 * Our own background plate.
 *
 * Keeping the blur/tint as subviews means SpringBoard may freely animate or
 * change the alpha of the parent background view without recreating Apple's
 * original blur material that caused Test3's page-reuse bug.
 */
@interface GFGlassFolderPlateView : UIView
@property (nonatomic, strong) UIVisualEffectView *gfBlurView;
@property (nonatomic, strong) UIView *gfTintView;
@property (nonatomic, assign) CGFloat gfStrength;
- (instancetype)initWithStrength:(CGFloat)strength;
@end

@implementation GFGlassFolderPlateView

- (instancetype)initWithStrength:(CGFloat)strength {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _gfStrength = MIN(1.0, MAX(0.0, strength));

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;

        UIBlurEffect *effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];

        _gfBlurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        _gfBlurView.userInteractionEnabled = NO;
        _gfBlurView.alpha = _gfStrength;
        [self addSubview:_gfBlurView];

        _gfTintView = [[UIView alloc] initWithFrame:CGRectZero];
        _gfTintView.userInteractionEnabled = NO;
        _gfTintView.backgroundColor = UIColor.whiteColor;

        /*
         * Very light tint. Blur does most of the visual work.
         * At 100% strength the tint is still intentionally subtle.
         */
        _gfTintView.alpha = 0.06 * _gfStrength;
        [self addSubview:_gfTintView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gfBlurView.frame = self.bounds;
    self.gfTintView.frame = self.bounds;

    /*
     * Follow SpringBoard's own rounded geometry rather than forcing a new
     * radius when possible. If SpringBoard has already assigned a radius to
     * the container, inherit it.
     */
    if (self.superview) {
        CGFloat inheritedRadius = self.superview.layer.cornerRadius;
        if (inheritedRadius > 0.0) {
            self.layer.cornerRadius = inheritedRadius;
        }
    }
}

@end


@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end

%hook SBFolderIconImageView

- (void)setBackgroundView:(UIView *)backgroundView {
    /*
     * Preferences are read here as a safety measure so a Respring is enough
     * to apply settings without relying on a background daemon.
     */
    GFLoadPreferences();

    if (!GFEnabled) {
        // Plugin disabled: leave Apple's original folder plate untouched.
        %orig(backgroundView);
        return;
    }

    GFGlassFolderPlateView *plate =
        [[GFGlassFolderPlateView alloc] initWithStrength:GFGlassStrength];

    %orig(plate);
}

%end

%ctor {
    @autoreleasepool {
        GFLoadPreferences();
    }
}
