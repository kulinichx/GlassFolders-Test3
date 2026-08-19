#ifndef GF_LIVE_PREFERENCES_PRELUDE_H
#define GF_LIVE_PREFERENCES_PRELUDE_H

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

/*
 * GlassFolders live preferences bridge.
 *
 * IMPORTANT:
 * This file is force-included before Tweak.xm by the Makefile.
 * Therefore it MUST NOT define or tentatively define any of Tweak.xm's
 * file-local static preference variables (GFEnabled, GFStyle, ...).
 *
 * We only forward-declare existing static FUNCTIONS. Function prototypes are
 * safe here; the real definitions appear later in the same translation unit.
 */

static CFStringRef const GFLivePreferencesDomain =
    CFSTR("com.kulinich.glassfolders");

static CFStringRef const GFLivePreferencesChangedNotification =
    CFSTR("com.kulinich.glassfolders/preferenceschanged");

/* Existing Tweak.xm helpers, defined later in the same translation unit. */
static void GFLoadPreferences(void);
static void GFUpdateOpenedFolderBackground(UIView *backgroundView);
static void GFUpdateRealAppLibraryPod(UIView *pod);
static void GFRefreshAppLibraryController(UIViewController *controller);

static NSUInteger GFLiveRefreshGeneration = 0;

static BOOL GFLiveReadBool(CFStringRef key, BOOL fallback) {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(key, GFLivePreferencesDomain);

    if (!value) return fallback;

    BOOL result = fallback;

    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int number = 0;
        CFNumberGetValue(
            (CFNumberRef)value,
            kCFNumberIntType,
            &number
        );
        result = (number != 0);
    }

    CFRelease(value);
    return result;
}

static NSInteger GFLiveReadInteger(
    CFStringRef key,
    NSInteger fallback
) {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(key, GFLivePreferencesDomain);

    if (!value) return fallback;

    long long number = fallback;

    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue(
            (CFNumberRef)value,
            kCFNumberLongLongType,
            &number
        );
    }

    CFRelease(value);
    return (NSInteger)number;
}

static CGFloat GFLiveReadPercent(
    CFStringRef key,
    CGFloat fallbackPercent
) {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(key, GFLivePreferencesDomain);

    if (!value) {
        return MIN(
            1.0,
            MAX(0.0, fallbackPercent / 100.0)
        );
    }

    double number = fallbackPercent;

    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue(
            (CFNumberRef)value,
            kCFNumberDoubleType,
            &number
        );
    }

    CFRelease(value);

    return MIN(
        1.0,
        MAX(0.0, (CGFloat)number / 100.0)
    );
}

static NSInteger GFLiveFolderStyle(void) {
    NSInteger style =
        GFLiveReadInteger(CFSTR("Style"), 0);

    return (style == 1) ? 1 : 0;
}

static CGFloat GFLiveFolderStrengthForStyle(
    NSInteger style
) {
    /*
     * Match GFLoadPreferences' migration behavior closely enough for
     * already-existing glass views.
     */
    CGFloat legacy =
        GFLiveReadPercent(CFSTR("GlassStrength"), 55.0);

    if (style == 0) {
        return GFLiveReadPercent(
            CFSTR("ClearStrength"),
            legacy * 100.0
        );
    }

    return GFLiveReadPercent(
        CFSTR("LiquidGlassStrength"),
        legacy * 100.0
    );
}

static void GFLiveSendNoArg(
    id object,
    NSString *selectorName
) {
    if (!object || selectorName.length == 0) return;

    SEL selector =
        NSSelectorFromString(selectorName);

    if (![object respondsToSelector:selector]) return;

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );
}

static void GFLiveSetNumberForKey(
    id object,
    NSNumber *value,
    NSString *key
) {
    if (!object || !value || key.length == 0) return;

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static void GFLiveRefreshViewTree(UIView *view) {
    if (!view) return;

    NSString *className =
        NSStringFromClass(view.class);

    /*
     * Open-folder host:
     * Existing GlassFolders code owns creation/removal and restoration of
     * stock material children. Calling it after GFLoadPreferences() makes the
     * enable/disable state live for an already-open folder.
     */
    if ([className isEqualToString:
            @"SBFolderBackgroundView"]) {
        GFUpdateOpenedFolderBackground(view);
    }

    /*
     * App Library category cards:
     * Reuse the project's authoritative update function.
     */
    if ([className isEqualToString:
            @"SBHLibraryCategoryPodBackgroundView"]) {
        GFUpdateRealAppLibraryPod(view);
    }

    /*
     * Existing folder glass instances retain style/strength as instance
     * properties, so update those from preferences and ask the object's own
     * material engine to rebuild itself.
     *
     * No access to Tweak.xm's static variables is needed here.
     */
    if ([className isEqualToString:
            @"GFBackdropGlassView"] ||
        [className isEqualToString:
            @"GFPanelGlassView"]) {

        NSInteger style =
            GFLiveFolderStyle();

        CGFloat strength =
            GFLiveFolderStrengthForStyle(style);

        GFLiveSetNumberForKey(
            view,
            @(style),
            @"gfStyle"
        );

        GFLiveSetNumberForKey(
            view,
            @(strength),
            @"gfStrength"
        );

        GFLiveSendNoArg(
            view,
            @"gfRefreshMaterial"
        );

        [view setNeedsLayout];
    }

    /*
     * App Library glass reads its effective style/preset from the project's
     * refreshed global preference state inside gfRefreshMaterial.
     */
    if ([className isEqualToString:
            @"GFAppLibraryGlassView"]) {
        GFLiveSendNoArg(
            view,
            @"gfRefreshMaterial"
        );

        [view setNeedsLayout];
    }

    /*
     * Closed folder icons only receive a new native/GlassFolders background
     * when SpringBoard asks SBFolderIconImageView to set one. We deliberately
     * do not fabricate a private stock background here.
     *
     * Style/strength changes are already applied to the current
     * GFBackdropGlassView above. Enable/disable settles through SpringBoard's
     * normal icon relayout/reconfiguration after returning from Settings.
     */
    if ([className isEqualToString:
            @"SBFolderIconImageView"]) {
        [view setNeedsDisplay];
        [view setNeedsLayout];
    }

    NSArray<UIView *> *children =
        [view.subviews copy];

    for (UIView *subview in children) {
        GFLiveRefreshViewTree(subview);
    }
}

static void GFLiveRefreshControllerTree(
    UIViewController *controller
) {
    if (!controller) return;

    NSString *className =
        NSStringFromClass(controller.class);

    if ([className containsString:
            @"SBLibraryViewController"]) {
        GFRefreshAppLibraryController(controller);
    }

    for (UIViewController *child
         in controller.childViewControllers) {
        GFLiveRefreshControllerTree(child);
    }

    UIViewController *presented =
        controller.presentedViewController;

    if (presented) {
        GFLiveRefreshControllerTree(presented);
    }
}

static void GFLiveRefreshAllSurfaces(void) {
    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application) return;

    for (UIScene *scene
         in application.connectedScenes) {

        if (![scene isKindOfClass:
                UIWindowScene.class]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        for (UIWindow *window
             in windowScene.windows) {

            if (!window) continue;

            GFLiveRefreshViewTree(window);

            if (window.rootViewController) {
                GFLiveRefreshControllerTree(
                    window.rootViewController
                );
            }
        }
    }
}

static void GFLiveApplyPreferencesNow(void) {
    /*
     * This is the authoritative existing GlassFolders loader.
     * It updates GFEnabled/GFStyle/strength/App Library globals internally.
     */
    GFLoadPreferences();

    GFLiveRefreshAllSurfaces();

    /*
     * SpringBoard/App Library may relayout one phase after returning from
     * Settings, so do one cheap settling pass.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.18 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            GFLiveRefreshAllSurfaces();
        }
    );
}

static void GFLiveSchedulePreferenceReload(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            NSUInteger generation =
                ++GFLiveRefreshGeneration;

            /*
             * Coalesce rapid slider writes so backdrop/SDF work is not rebuilt
             * for every raw UISlider event.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(0.10 * NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    if (generation !=
                        GFLiveRefreshGeneration) {
                        return;
                    }

                    GFLiveApplyPreferencesNow();
                }
            );
        }
    );
}

static void GFLivePreferencesDarwinCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;

    GFLiveSchedulePreferenceReload();
}

@interface GFLiveActivationObserver : NSObject
@end

@implementation GFLiveActivationObserver

- (void)gfApplicationDidBecomeActive:
    (__unused NSNotification *)notification {
    GFLiveSchedulePreferenceReload();
}

@end

__attribute__((constructor))
static void GFLivePreferencesInstall(void) {
    @autoreleasepool {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            GFLivePreferencesDarwinCallback,
            GFLivePreferencesChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        static GFLiveActivationObserver
            *activationObserver = nil;

        activationObserver =
            [GFLiveActivationObserver new];

        [[NSNotificationCenter defaultCenter]
            addObserver:activationObserver
               selector:@selector(
                   gfApplicationDidBecomeActive:
               )
                   name:
                       UIApplicationDidBecomeActiveNotification
                 object:nil];
    }
}

#endif /* GF_LIVE_PREFERENCES_PRELUDE_H */
