// Production legibility routing and restoration, not SpringBoard visual QA.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>

typedef double CGFloat;
typedef NS_ENUM(NSInteger, UIUserInterfaceStyle) {
    UIUserInterfaceStyleUnspecified, UIUserInterfaceStyleLight, UIUserInterfaceStyleDark
};
@interface UITraitCollection : NSObject
@end
@implementation UITraitCollection
@end

@interface UIColor : NSObject
@property double white;
@property double alpha;
+ (instancetype)colorWithWhite:(double)white alpha:(double)alpha;
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits;
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a;
@end
@implementation UIColor
+ (instancetype)colorWithWhite:(double)white alpha:(double)alpha {
    UIColor *color = [self new]; color.white = white; color.alpha = alpha; return color;
}
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits { return self; }
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a {
    *r = *g = *b = self.white; *a = self.alpha; return YES;
}
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a {
    *w = self.white; *a = self.alpha; return YES;
}
@end

@interface _UILegibilitySettings : NSObject
@property (strong) UIColor *primaryColor;
@property (strong) UIColor *secondaryColor;
@property (strong) UIColor *shadowColor;
@property double shadowRadius;
@end
@implementation _UILegibilitySettings
@end

@interface SBUIController : NSObject
@property (strong) id homeSettings;
@property NSUInteger reads;
+ (instancetype)sharedInstance;
- (id)_currentHomeScreenLegibilitySettings;
@end
@implementation SBUIController
+ (instancetype)sharedInstance {
    static SBUIController *value;
    if (!value) value = [self new];
    return value;
}
- (id)_currentHomeScreenLegibilitySettings { self.reads++; return self.homeSettings; }
@end

@interface SBWallpaperController : NSObject
@property (strong) id settings;
@property NSUInteger reads;
@property NSInteger lastVariant;
+ (instancetype)sharedInstance;
- (id)legibilitySettingsForVariant:(NSInteger)variant;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {
    static SBWallpaperController *value;
    if (!value) value = [self new];
    return value;
}
- (id)legibilitySettingsForVariant:(NSInteger)variant {
    self.reads++; self.lastVariant = variant; return self.settings;
}
@end

@interface UIView : NSObject
@property (strong) UITraitCollection *traitCollection;
@property (copy) NSArray<UIView *> *subviews;
@property UIUserInterfaceStyle overrideUserInterfaceStyle;
@property BOOL insideLibrary;
@end
@implementation UIView
- (instancetype)init {
    self = [super init];
    if (self) { _traitCollection = [UITraitCollection new]; _subviews = @[]; }
    return self;
}
@end
@interface UIViewController : NSObject
@property (strong) UIView *view;
@property (getter=isViewLoaded) BOOL viewLoaded;
@end
@implementation UIViewController
@end

static BOOL GFAppLibraryGlassEnabled = YES;
static BOOL TestReduceTransparency, TestIncreaseContrast;
static BOOL UIAccessibilityIsReduceTransparencyEnabled(void) { return TestReduceTransparency; }
static BOOL UIAccessibilityDarkerSystemColorsEnabled(void) { return TestIncreaseContrast; }
#import "../GFLibraryLegibility.h"
static BOOL GFViewIsInsideAppLibrary(UIView *view) { return view.insideLibrary; }

@interface TestLibraryController : UIViewController
@property (strong) id nativeSettings;
@property (strong) id appliedSettings;
@property NSUInteger updates;
- (id)effectiveLegibilitySettings;
- (void)_updateViewControllerLegibility;
@end
@implementation TestLibraryController
- (id)effectiveLegibilitySettings {
    return GFLibraryEffectiveLegibility(self.nativeSettings, self.view.traitCollection);
}
- (void)_updateViewControllerLegibility {
    self.updates++;
    self.appliedSettings = [self effectiveLegibilitySettings];
    GFLibraryRefreshControllerLegibility(self);
}
@end

@interface SBHSearchTextField : UIView
@property NSUInteger styleUpdates;
@property (copy) NSString *text;
@property (copy) NSString *placeholder;
@property (strong) id font;
@property (strong) id attributedPlaceholder;
- (void)updateVisualStyling;
@end
@implementation SBHSearchTextField
- (void)updateVisualStyling {
    self.styleUpdates++;
    GFLibraryRefreshSearchField(self, self.insideLibrary);
}
@end

@interface WrongGetter : NSObject
- (NSInteger)effectiveLegibilitySettings;
@end
@implementation WrongGetter
- (NSInteger)effectiveLegibilitySettings { return 0; }
@end
@interface WrongUpdater : NSObject
- (id)_updateViewControllerLegibility;
@end
@implementation WrongUpdater
- (id)_updateViewControllerLegibility { return nil; }
@end

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    @autoreleasepool {
        UIColor *black = [UIColor colorWithWhite:0 alpha:1];
        UIColor *white = [UIColor colorWithWhite:1 alpha:1];
        _UILegibilitySettings *home = [_UILegibilitySettings new];
        home.primaryColor = black; home.secondaryColor = black;
        home.shadowColor = white; home.shadowRadius = 2.5;
        _UILegibilitySettings *native = [_UILegibilitySettings new];
        native.primaryColor = white;
        SBUIController *provider = [SBUIController sharedInstance];
        SBWallpaperController *wallpaper = [SBWallpaperController sharedInstance];
        provider.homeSettings = home;
        // The system's effective Home settings take precedence over wallpaper fallback.
        wallpaper.settings = native;
        GFHomeInvalidateWallpaper();
        TestLibraryController *controller = [TestLibraryController new];
        controller.view = [UIView new]; controller.viewLoaded = YES;
        controller.nativeSettings = native;
        GFLibraryLegibilityHookAvailable = YES;
        GFLibraryRefreshControllerLegibility(controller);
        CHECK(controller.appliedSettings == home && controller.nativeSettings == native);
        CHECK(home.shadowColor == white && home.shadowRadius == 2.5);
        CHECK(controller.updates == 1 && provider.reads == 1 && wallpaper.reads == 0);
        for (NSUInteger i = 0; i < 100; i++) GFLibraryRefreshControllerLegibility(controller);
        CHECK(controller.updates == 1 && provider.reads == 1);
        // An in-place settings update must still refresh on the native event.
        home.primaryColor = white;
        GFHomeInvalidateWallpaper();
        GFLibraryRefreshControllerLegibility(controller);
        CHECK(controller.updates == 2 && controller.appliedSettings == home);

        SBHSearchTextField *field = [SBHSearchTextField new];
        field.traitCollection = controller.view.traitCollection;
        field.insideLibrary = YES;
        field.text = @"query"; field.placeholder = @"App Library";
        field.font = [NSObject new]; field.attributedPlaceholder = [NSObject new];
        id font = field.font, attributed = field.attributedPlaceholder;
        // Native light foreground requests system dark-appearance styling.
        GFLibraryRefreshSearchField(field, YES);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        CHECK(field.styleUpdates == 1);
        home.primaryColor = black;
        GFHomeInvalidateWallpaper();
        GFLibraryRefreshSearchField(field, YES);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleLight);
        NSUInteger writes = field.styleUpdates;
        for (NSUInteger i = 0; i < 100; i++) [field updateVisualStyling];
        CHECK(field.styleUpdates == writes + 100);
        CHECK(field.font == font && field.attributedPlaceholder == attributed);
        CHECK([field.text isEqual:@"query"] && [field.placeholder isEqual:@"App Library"]);

        GFAppLibraryGlassEnabled = NO;
        GFLibraryRefreshControllerLegibility(controller);
        GFLibraryRefreshSearchField(field, YES);
        CHECK(controller.appliedSettings == native && controller.nativeSettings == native);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified);
        GFAppLibraryGlassEnabled = YES;
        GFLibraryRefreshSearchField(field, YES);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleLight);
        field.insideLibrary = NO;
        GFLibraryRefreshSearchField(field, NO);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified);

        // Do not overwrite a newer native appearance when restoring a reused field.
        field.insideLibrary = YES;
        GFLibraryRefreshSearchField(field, YES);
        field.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        GFLibraryRefreshSearchField(field, NO);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        field.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        GFLibraryRefreshSearchField(field, YES);
        TestReduceTransparency = YES;
        GFLibraryRefreshControllerLegibility(controller);
        GFLibraryRefreshSearchField(field, YES);
        CHECK(controller.appliedSettings == native);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified);
        TestReduceTransparency = NO;
        GFLibraryRefreshSearchField(field, YES);
        TestIncreaseContrast = YES;
        GFLibraryRefreshSearchField(field, YES);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified);
        TestIncreaseContrast = NO;

        // No valid native input means no invented black/white settings.
        provider.homeSettings = nil;
        GFHomeInvalidateWallpaper();
        CHECK(GFLibraryHomeLegibility(field.traitCollection) == native);
        CHECK(wallpaper.lastVariant == 1);
        wallpaper.settings = nil;
        GFHomeInvalidateWallpaper();
        CHECK(GFLibraryEffectiveLegibility(native, field.traitCollection) == native);
        NSUInteger reads = provider.reads;
        for (NSUInteger i = 0; i < 100; i++)
            CHECK(!GFLibraryHomeLegibility(field.traitCollection));
        CHECK(provider.reads == reads);
        provider.homeSettings = [NSObject new];
        GFHomeInvalidateWallpaper();
        CHECK(!GFLibraryHomeLegibility(field.traitCollection));
        provider.homeSettings = home;
        home.primaryColor = [UIColor colorWithWhite:NAN alpha:1];
        GFHomeInvalidateWallpaper();
        CHECK(!GFLibraryHomeLegibility(field.traitCollection));
        home.primaryColor = [UIColor colorWithWhite:0 alpha:.4];
        GFHomeInvalidateWallpaper();
        CHECK(!GFLibraryHomeLegibility(field.traitCollection));
        home.primaryColor = black;
        GFHomeInvalidateWallpaper();
        CHECK(GFLibraryHomeLegibility(field.traitCollection) == home);

        UIView *root = [UIView new];
        field.insideLibrary = YES;
        UIView *ordinary = [UIView new];
        ordinary.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        root.subviews = @[field, ordinary];
        GFLibraryRefreshSearchTree(root, YES);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleLight);
        CHECK(ordinary.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        GFLibraryRefreshSearchTree(root, NO);
        CHECK(field.overrideUserInterfaceStyle == UIUserInterfaceStyleUnspecified);
        CHECK(!GFLibraryHasMethod(WrongGetter.class, @"effectiveLegibilitySettings", '@'));
        CHECK(!GFLibraryHasMethod(WrongUpdater.class, @"_updateViewControllerLegibility", 'v'));
        puts("Production library legibility: native settings identity/shadows, native "
             "propagation, cache/reentrancy, in-place updates, scoped search appearance, "
             "restoration/reuse, accessibility, invalid input and ABI checks PASS");
    }
    return 0;
}
