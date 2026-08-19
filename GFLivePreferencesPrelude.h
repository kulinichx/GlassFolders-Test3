#ifndef GF_LIVE_PREFERENCES_PRELUDE_H
#define GF_LIVE_PREFERENCES_PRELUDE_H

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

/*
 * GlassFolders live preferences bridge.
 *
 * This header is force-included into Tweak.xm by the Makefile so it shares
 * the same translation unit as GlassFolders' existing static state/functions.
 * The material engine itself is not duplicated or rewritten.
 */

static CFStringRef const GFLivePreferencesChangedNotification =
    CFSTR("com.kulinich.glassfolders/preferenceschanged");

/*
 * Tentative declarations for the existing file-local preference state.
 * Tweak.xm later provides the initialized definitions.
 */
static BOOL GFEnabled;
static NSInteger GFStyle;
static CGFloat GFClearStrength;
static CGFloat GFLiquidGlassStrength;
static CGFloat GFGlassStrength;
static BOOL GFAppLibraryGlassEnabled;
static NSInteger GFAppLibraryStyle;
static NSInteger GFAppLibraryStyleMode;
static NSInteger GFAppLibraryClearPreset;
static NSInteger GFAppLibraryLiquidPreset;
static CGFloat GFAppLibraryGlassStrength;

/* Existing Tweak.xm helpers, defined later in the same translation unit. */
static void GFLoadPreferences(void);
static BOOL GFViewIsInsideAppLibrary(UIView *view);
static void GFUpdateOpenedFolderBackground(UIView *backgroundView);
static void GFUpdateRealAppLibraryPod(UIView *pod);
static void GFRefreshAppLibraryController(UIViewController *controller);

static NSUInteger GFLiveRefreshGeneration = 0;

static inline void GFLiveSendNoArg(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0) return;

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return;

    ((void (*)(id, SEL))objc_msgSend)(object, selector);
}

static inline void GFLiveSetNumberForKey(id object,
                                         NSNumber *value,
                                         NSString *key) {
    if (!object || !value || key.length == 0) return;

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static UIView *GFLiveFindSubviewNamed(UIView *root, NSString *className) {
    if (!root || className.length == 0) return nil;

    if ([NSStringFromClass(root.class) isEqualToString:className]) {
        return root;
    }

    for (UIView *subview in root.subviews) {
        UIView *match = GFLiveFindSubviewNamed(subview, className);
        if (match) return match;
    }

    return nil;
}

static void GFLiveCollectAndRefreshViews(UIView *view,
                                         NSMutableArray<UIView *> *folderIcons) {
    if (!view) return;

    NSString *className = NSStringFromClass(view.class);

    if ([className isEqualToString:@"GFPanelGlassView"]) {
        GFLiveSetNumberForKey(view, @(GFStyle), @"gfStyle");
        GFLiveSetNumberForKey(view, @(GFGlassStrength), @"gfStrength");
        GFLiveSendNoArg(view, @"gfRefreshMaterial");
        [view setNeedsLayout];
    } else if ([className isEqualToString:@"GFAppLibraryGlassView"]) {
        /*
         * App Library overlays derive their recipe from the refreshed globals.
         * Their own strength remains intentionally fixed by the existing code.
         */
        GFLiveSendNoArg(view, @"gfRefreshMaterial");
        [view setNeedsLayout];
    } else if ([className isEqualToString:
                @"SBHLibraryCategoryPodBackgroundView"]) {
        GFUpdateRealAppLibraryPod(view);
    } else if ([className isEqualToString:@"SBFolderBackgroundView"]) {
        GFUpdateOpenedFolderBackground(view);
    } else if ([className isEqualToString:@"SBFolderIconImageView"]) {
        [folderIcons addObject:view];
    }

    for (UIView *subview in [view.subviews copy]) {
        GFLiveCollectAndRefreshViews(subview, folderIcons);
    }

    [view setNeedsLayout];
}

static void GFLiveRefreshControllerTree(UIViewController *controller) {
    if (!controller) return;

    NSString *className = NSStringFromClass(controller.class);
    if ([className containsString:@"SBLibraryViewController"]) {
        GFRefreshAppLibraryController(controller);
    }

    for (UIViewController *child in controller.childViewControllers) {
        GFLiveRefreshControllerTree(child);
    }

    UIViewController *presented = controller.presentedViewController;
    if (presented) {
        GFLiveRefreshControllerTree(presented);
    }
}

static void GFLiveRefreshClosedFolderIcon(UIView *iconView) {
    if (!iconView) return;

    [iconView setNeedsDisplay];
    [iconView setNeedsLayout];

    /*
     * If folder glass is already active, rebuild the currently-installed plate
     * through GlassFolders' own setBackgroundView: hook. That gives style and
     * strength changes an immediate result without duplicating the material
     * construction logic here.
     *
     * Enabling/disabling the folder effect itself is left to SpringBoard's
     * normal icon reconfiguration on scene activation/layout; no respring is
     * required.
     */
    if (!GFEnabled || GFViewIsInsideAppLibrary(iconView)) {
        return;
    }

    UIView *currentGlass =
        GFLiveFindSubviewNamed(iconView, @"GFBackdropGlassView");

    SEL setBackgroundSelector =
        NSSelectorFromString(@"setBackgroundView:");

    if (currentGlass &&
        [iconView respondsToSelector:setBackgroundSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(
            iconView,
            setBackgroundSelector,
            currentGlass
        );
    }
}

static void GFLiveRefreshAllSurfaces(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (!application) return;

    NSMutableArray<UIView *> *folderIcons =
        [NSMutableArray array];

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {
            if (!window) continue;

            GFLiveCollectAndRefreshViews(window, folderIcons);

            if (window.rootViewController) {
                GFLiveRefreshControllerTree(
                    window.rootViewController
                );
            }
        }
    }

    for (UIView *iconView in folderIcons) {
        GFLiveRefreshClosedFolderIcon(iconView);
    }
}

static void GFLiveApplyPreferencesNow(void) {
    /*
     * Reuse the real GlassFolders loader so defaults, migration and style
     * selection stay exactly in sync with the existing tweak.
     */
    GFLoadPreferences();

    /*
     * One immediate pass updates currently-existing surfaces. A short second
     * pass catches SpringBoard/App Library views that are relaid out one phase
     * later after returning from Settings.
     */
    GFLiveRefreshAllSurfaces();

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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger generation =
            ++GFLiveRefreshGeneration;

        /*
         * Settings sliders can emit many writes while dragging. Coalesce them
         * so expensive backdrop/SDF refresh work happens only after activity
         * settles instead of once per raw UISlider event.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.10 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                if (generation != GFLiveRefreshGeneration) {
                    return;
                }

                GFLiveApplyPreferencesNow();
            }
        );
    });
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
    /*
     * SpringBoard may have been visually covered by Settings when the Darwin
     * notification arrived. Re-run the cheap surface refresh when Home becomes
     * active so enable/disable and recycled icon views settle without respring.
     */
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

        static GFLiveActivationObserver *activationObserver = nil;
        activationObserver = [GFLiveActivationObserver new];

        [[NSNotificationCenter defaultCenter]
            addObserver:activationObserver
               selector:@selector(gfApplicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    }
}

#endif /* GF_LIVE_PREFERENCES_PRELUDE_H */
