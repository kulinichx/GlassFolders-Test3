#ifndef GF_LIBRARY_LEGIBILITY_H
#define GF_LIBRARY_LEGIBILITY_H

#import "GFHomeScreenPalette.h"

static BOOL GFViewIsInsideAppLibrary(UIView *view);
static BOOL GFLibraryLegibilityHookAvailable = NO;

static BOOL GFLibraryHasMethod(Class cls, NSString *name, char returnType) {
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(name)) : NULL;
    char result[8] = {0};
    if (method) method_getReturnType(method, result, sizeof(result));
    return method && method_getNumberOfArguments(method) == 2 && result[0] == returnType;
}

static BOOL GFLibraryAdaptationEnabled(void) {
    return GFAppLibraryGlassEnabled &&
        !UIAccessibilityIsReduceTransparencyEnabled() &&
        !UIAccessibilityDarkerSystemColorsEnabled();
}

static BOOL GFLibraryReadSettings(id settings, UITraitCollection *traits,
                                  BOOL *lightAppearance) {
    Class settingsClass = objc_getClass("_UILegibilitySettings");
    if (!settingsClass || ![settings isKindOfClass:settingsClass]) return NO;
    double rgba[4];
    if (!GFHomeReadColor(GFHomeObject(settings, @"primaryColor"), traits, rgba)) return NO;
    GFNotificationPalette foreground = GFNotificationPaletteForWallpaper(
        rgba[0], rgba[1], rgba[2], rgba[3], false, false);
    if (!foreground.valid) return NO;
    // Classify the system's foreground, not the wallpaper or interface mode.
    if (lightAppearance) *lightAppearance = foreground.luminance < 0.18;
    return YES;
}

@interface GFLibrarySystemLegibility : NSObject
@property (nonatomic, weak) id controller;
@property (nonatomic, weak) id wallpaper;
@property (nonatomic, strong) id settings;
@property (nonatomic, strong) UITraitCollection *traits;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL attempted;
- (id)settingsForTraits:(UITraitCollection *)traits;
@end

@implementation GFLibrarySystemLegibility
- (id)settingsForTraits:(UITraitCollection *)traits {
    id controller = GFHomeObject((id)objc_getClass("SBUIController"), @"sharedInstance");
    id wallpaper = GFHomeObject((id)objc_getClass("SBWallpaperController"), @"sharedInstance");
    if (!self.attempted || self.generation != GFHomeWallpaperGeneration ||
        self.controller != controller || self.wallpaper != wallpaper ||
        ![self.traits isEqual:traits]) {
        self.attempted = YES;
        self.generation = GFHomeWallpaperGeneration;
        self.controller = controller;
        self.wallpaper = wallpaper;
        self.traits = traits;
        id settings = GFHomeObject(controller, @"_currentHomeScreenLegibilitySettings");
        if (!GFLibraryReadSettings(settings, traits, NULL))
            settings = GFHomeVariantObject(wallpaper, @"legibilitySettingsForVariant:");
        self.settings = GFLibraryReadSettings(settings, traits, NULL) ? settings : nil;
    }
    return GFLibraryReadSettings(self.settings, traits, NULL) ? self.settings : nil;
}
@end

static id GFLibraryHomeLegibility(UITraitCollection *traits) {
    static GFLibrarySystemLegibility *state;
    if (!state) state = [GFLibrarySystemLegibility new];
    return [state settingsForTraits:traits];
}

static id GFLibraryEffectiveLegibility(id native, UITraitCollection *traits) {
    if (!GFLibraryAdaptationEnabled()) return native;
    // Keep Apple's full settings object, including image-label shadows.
    return GFLibraryHomeLegibility(traits) ?: native;
}

@interface GFLibraryControllerLegibility : NSObject
@property (nonatomic, strong) id settings;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL updating;
@property (nonatomic, assign) NSUInteger generation;
@end
@implementation GFLibraryControllerLegibility
@end

static char kGFLibraryControllerLegibilityKey;
static void GFLibraryRefreshControllerLegibility(UIViewController *controller) {
    if (!GFLibraryLegibilityHookAvailable || !controller.isViewLoaded ||
        !GFLibraryHasMethod(object_getClass(controller), @"_updateViewControllerLegibility", 'v'))
        return;
    GFLibraryControllerLegibility *state =
        objc_getAssociatedObject(controller, &kGFLibraryControllerLegibilityKey);
    if (state.updating) return;
    BOOL active = GFLibraryAdaptationEnabled() &&
        GFLibraryHomeLegibility(controller.view.traitCollection) != nil;
    if (!active && !state) return;
    id settings = GFHomeObject(controller, @"effectiveLegibilitySettings");
    if (state && state.generation == GFHomeWallpaperGeneration && state.active == active &&
        (state.settings == settings || [state.settings isEqual:settings])) return;
    if (!state) {
        state = [GFLibraryControllerLegibility new];
        objc_setAssociatedObject(controller, &kGFLibraryControllerLegibilityKey,
                                 state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.settings = settings;
    state.active = active;
    state.generation = GFHomeWallpaperGeneration;
    state.updating = YES;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(
            controller, NSSelectorFromString(@"_updateViewControllerLegibility"));
    } @finally {
        state.updating = NO;
    }
}

@interface GFLibrarySearchAppearance : NSObject
@property (nonatomic, assign) UIUserInterfaceStyle nativeStyle;
@property (nonatomic, assign) UIUserInterfaceStyle appliedStyle;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL updating;
@end
@implementation GFLibrarySearchAppearance
@end

static char kGFLibrarySearchAppearanceKey;
static void GFLibraryRefreshSearchField(UIView *field, BOOL inLibrary) {
    GFLibrarySearchAppearance *state =
        objc_getAssociatedObject(field, &kGFLibrarySearchAppearanceKey);
    if (state.updating) return;
    id settings = inLibrary && GFLibraryAdaptationEnabled()
        ? GFLibraryHomeLegibility(field.traitCollection) : nil;
    BOOL light = NO;
    BOOL active = GFLibraryReadSettings(settings, field.traitCollection, &light);
    if (!active && !state) return;
    if (!state) {
        state = [GFLibrarySearchAppearance new];
        objc_setAssociatedObject(field, &kGFLibrarySearchAppearanceKey,
                                 state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIUserInterfaceStyle current = field.overrideUserInterfaceStyle;
    if (active && (!state.active || current != state.appliedStyle))
        state.nativeStyle = current;
    UIUserInterfaceStyle target = light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    BOOL change = active ? current != target
        : state.active && current == state.appliedStyle && current != state.nativeStyle;
    state.updating = YES;
    state.active = active;
    if (active) state.appliedStyle = target;
    @try {
        if (change) {
            field.overrideUserInterfaceStyle = active ? target : state.nativeStyle;
            if (GFLibraryHasMethod(object_getClass(field), @"updateVisualStyling", 'v'))
                ((void (*)(id, SEL))objc_msgSend)(field, NSSelectorFromString(@"updateVisualStyling"));
        }
    } @finally {
        state.updating = NO;
    }
}

static void GFLibraryRefreshSearchTree(UIView *root, BOOL inLibrary) {
    if (!root) return;
    Class fieldClass = objc_getClass("SBHSearchTextField");
    if (fieldClass && [root isKindOfClass:fieldClass]) {
        GFLibraryRefreshSearchField(root, inLibrary && GFViewIsInsideAppLibrary(root));
        return;
    }
    for (UIView *child in root.subviews)
        GFLibraryRefreshSearchTree(child, inLibrary);
}

#endif
