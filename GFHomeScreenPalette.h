#ifndef GF_HOME_SCREEN_PALETTE_H
#define GF_HOME_SCREEN_PALETTE_H

#import "GFNotificationPalette.h"
#include <string.h>

static id GFHomeObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 || type[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id GFHomeVariantObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    char result[8] = {0}, argument[8] = {0};
    if (method) {
        method_getReturnType(method, result, sizeof(result));
        method_getArgumentType(method, 2, argument, sizeof(argument));
    }
    if (!method || method_getNumberOfArguments(method) != 3 || result[0] != '@' ||
        strcmp(argument, @encode(NSInteger)) != 0) return nil;
    // SpringBoard wallpaper variants: 0 lock screen, 1 Home Screen.
    return ((id (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, 1);
}

static BOOL GFHomeScreenVisible(void) {
    id application = GFHomeObject((id)objc_getClass("UIApplication"), @"sharedApplication");
    SEL selector = NSSelectorFromString(@"isShowingHomescreen");
    Method method = application ?
        class_getInstanceMethod(object_getClass(application), selector) : NULL;
    char result[8] = {0};
    if (method) method_getReturnType(method, result, sizeof(result));
    if (!method || method_getNumberOfArguments(method) != 2 ||
        (result[0] != 'B' && result[0] != 'c')) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(application, selector);
}

static NSUInteger GFHomeWallpaperGeneration = 1;
static void GFHomeInvalidateWallpaper(void) {
    GFHomeWallpaperGeneration++;
}

static BOOL GFHomeReadColor(id value, UITraitCollection *traits, double rgba[4]) {
    if (![value isKindOfClass:UIColor.class]) return NO;
    UIColor *color = [(UIColor *)value resolvedColorWithTraitCollection:traits];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        if (![color getWhite:&r alpha:&a]) return NO;
        g = b = r;
    }
    rgba[0] = r; rgba[1] = g; rgba[2] = b; rgba[3] = a;
    return YES;
}

@interface GFHomeWallpaperState : NSObject
@property (nonatomic, weak) id provider;
@property (nonatomic, strong) UITraitCollection *traits;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) GFNotificationPalette palette;
@property (nonatomic, assign) BOOL attempted;
- (GFNotificationPalette)paletteForTraits:(UITraitCollection *)traits;
@end

@implementation GFHomeWallpaperState
- (GFNotificationPalette)paletteForTraits:(UITraitCollection *)traits {
    id provider = GFHomeObject((id)objc_getClass("SBWallpaperController"), @"sharedInstance");
    if (self.attempted && self.generation == GFHomeWallpaperGeneration &&
        self.provider == provider && [self.traits isEqual:traits]) return self.palette;
    self.provider = provider;
    self.traits = traits;
    self.generation = GFHomeWallpaperGeneration;
    self.attempted = YES;
    double rgba[4];
    GFNotificationPalette result = {0};
    id average = GFHomeVariantObject(provider, @"averageColorForVariant:");
    if (GFHomeReadColor(average, traits, rgba)) {
        result = GFNotificationPaletteForWallpaper(rgba[0], rgba[1], rgba[2], rgba[3],
                                                   self.palette.valid, self.palette.lightSurface);
    }
    if (!result.valid) {
        id settings = GFHomeVariantObject(provider, @"legibilitySettingsForVariant:");
        if (!settings) {
            id controller = GFHomeObject((id)objc_getClass("SBUIController"), @"sharedInstance");
            settings = GFHomeObject(controller, @"_currentHomeScreenLegibilitySettings");
        }
        if (GFHomeReadColor(GFHomeObject(settings, @"primaryColor"), traits, rgba) &&
            rgba[3] >= 0.95) {
            GFNotificationPalette foreground = GFNotificationPaletteForWallpaper(
                rgba[0], rgba[1], rgba[2], rgba[3], false, false);
            if (foreground.valid)
                result = GFNotificationPaletteForAppearance(foreground.luminance < 0.18);
        }
    }
    self.palette = result;
    return result;
}
@end

static GFNotificationPalette GFHomeWallpaperPalette(UITraitCollection *traits) {
    // One shared, event-invalidated read serves banners and all library cards.
    static GFHomeWallpaperState *state;
    if (!state) state = [GFHomeWallpaperState new];
    return [state paletteForTraits:traits];
}

#endif
