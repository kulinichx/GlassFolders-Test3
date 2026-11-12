// Included after GFPanelGlassView. Only known system material backgrounds are
// replaced; notification content, remote activity scenes and controls stay intact.
#ifndef GF_LOCK_SCREEN_GLASS_H
#define GF_LOCK_SCREEN_GLASS_H

#import "GFGlassRim.h"
#import "GFNotificationForeground.h"
#import "GFGlassStrength.h"

// All enabled surfaces follow the active Clear/Liquid Glass strength.
// Keep wallpaper detail behind cards, and use still less blur for small buttons.
static const CGFloat GFLockCardBlurRadius = 8.0;
static const CGFloat GFNotificationLightBlurRadius = 3.0;
static const CGFloat GFNotificationDarkBlurRadius = 4.0;
static const CGFloat GFLockButtonBlurRadius = 3.0;

static void GFLockApplyBackdropRecipe(GFPanelGlassView *glass, NSString *group, CGFloat radius) {
    CALayer *backdrop = glass.gfBackdropSampleView.layer;
    if ([NSStringFromClass(backdrop.class) containsString:@"Backdrop"]) {
        // Peers using the same recipe share a capture group. Never filter in
        // place: overlapping/animated notifications must not feed previously
        // brightened glass back into another glass pass.
        SEL groupSelector = NSSelectorFromString(@"setGroupName:");
        if ([backdrop respondsToSelector:groupSelector])
            ((void (*)(id, SEL, id))objc_msgSend)(backdrop, groupSelector, group);
        SEL inPlaceSelector = NSSelectorFromString(@"setAllowsInPlaceFiltering:");
        if ([backdrop respondsToSelector:inPlaceSelector])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(backdrop, inPlaceSelector, NO);
        NSMutableArray *filters = [NSMutableArray array];
        id saturate = GFCreateCAFilter(@"colorSaturate");
        if (saturate) {
            [saturate setValue:@1.04 forKey:@"inputAmount"];
            [filters addObject:saturate];
        }
        id blur = GFCreateCAFilter(@"gaussianBlur");
        if (blur && radius > 0.001) {
            [blur setValue:@(radius) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [filters addObject:blur];
        }
        // No additive brightness filter: it can accumulate across a stack.
        [backdrop setValue:filters forKey:@"filters"];
        glass.gfBackdropSampleView.alpha = 1.0;
    }
}

// GFLockRimView is shared with App Library via GFGlassRim.h.

@interface GFLockScreenGlassView : GFPanelGlassView
@property (nonatomic, assign) BOOL gfCircular;
@property (nonatomic, assign) BOOL gfUsesNotificationPalette;
@property (nonatomic, assign) GFNotificationPalette gfNotificationPalette;
@property (nonatomic, strong) GFLockRimView *gfLockRim;
@property (nonatomic, strong) CAGradientLayer *gfBodyVeil;
@property (nonatomic, assign) BOOL gfHasBackdropBlurRadius;
@property (nonatomic, assign) CGFloat gfAppliedBackdropBlurRadius;
- (void)gfRefreshBodyVeil;
- (void)gfApplyNotificationPalette:(GFNotificationPalette)palette;
- (void)gfClearNotificationPalette;
- (NSString *)gfBackdropGroupName;
- (CGFloat)gfBackdropBlurRadius;
- (void)gfRefreshBackdropBlurIfNeeded;
@end
@implementation GFLockScreenGlassView
- (instancetype)initWithStyle:(NSInteger)style strength:(CGFloat)strength {
    self = [super initWithStyle:style strength:strength];
    if (self) {
        self.gfBodyVeil = [CAGradientLayer layer];
        self.gfBodyVeil.startPoint = CGPointMake(0.3, 0.0);
        self.gfBodyVeil.endPoint = CGPointMake(0.7, 1.0);
        self.gfBodyVeil.locations = @[@0.0, @0.36, @0.72, @1.0];
        self.gfBodyVeil.zPosition = 19.0;
        [self.layer addSublayer:self.gfBodyVeil];
        self.gfLockRim = [[GFLockRimView alloc] initWithFrame:self.bounds];
        [self addSubview:self.gfLockRim];
        // The superclass refreshes during init, before the rim exists.
        [self gfRefreshMaterial];
    }
    return self;
}
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    // The superclass may replace filters even when our radius did not change.
    self.gfHasBackdropBlurRadius = NO;
    if (self.gfFallbackBlurView) {
        self.gfFallbackBlurView.effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    }
    [self gfRefreshBackdropBlurIfNeeded];
    // Keep the body neutral and low density; edge thickness comes from the
    // compact reflection. Folder strength stays separate.
    self.gfTintView.alpha = 0.0;
    self.gfOpticalLayer.hidden = YES;
    self.layer.borderWidth = 0.0;
    [self gfRefreshBodyVeil];
    [self.gfLockRim setNeedsLayout];
}
- (NSString *)gfBackdropGroupName {
    return @"com.kulinich.glassfolders.lock.cards";
}
- (CGFloat)gfBackdropBlurRadius {
    CGFloat radius = !self.gfUsesNotificationPalette ? GFLockCardBlurRadius :
        (self.gfNotificationPalette.lightSurface ?
         GFNotificationLightBlurRadius : GFNotificationDarkBlurRadius);
    return radius * GFSharedGlassScale(GFGlassStrength);
}
- (void)gfRefreshBackdropBlurIfNeeded {
    CGFloat radius = [self gfBackdropBlurRadius];
    if (self.gfHasBackdropBlurRadius && self.gfAppliedBackdropBlurRadius == radius) return;
    GFLockApplyBackdropRecipe(self, [self gfBackdropGroupName], radius);
    self.gfFallbackBlurView.alpha = 0.22 * GFSharedGlassScale(GFGlassStrength);
    self.gfAppliedBackdropBlurRadius = radius;
    self.gfHasBackdropBlurRadius = YES;
}
- (void)gfApplyNotificationPalette:(GFNotificationPalette)palette {
    if (self.gfUsesNotificationPalette &&
        self.gfNotificationPalette.lightSurface == palette.lightSurface &&
        self.gfNotificationPalette.bodyWhite == palette.bodyWhite &&
        self.gfNotificationPalette.bodyOpacity == palette.bodyOpacity) return;
    BOOL backdropChanged = !self.gfUsesNotificationPalette ||
        self.gfNotificationPalette.lightSurface != palette.lightSurface;
    self.gfUsesNotificationPalette = YES;
    self.gfNotificationPalette = palette;
    if (backdropChanged) {
        // Reconfigure only on a wallpaper-mode change, never a stack change.
        [self gfRefreshBackdropBlurIfNeeded];
    }
    self.gfLockRim.gfLightSurface = palette.lightSurface;
    [self gfRefreshBodyVeil];
    [self.gfLockRim setNeedsLayout];
}
- (void)gfClearNotificationPalette {
    if (!self.gfUsesNotificationPalette) return;
    self.gfUsesNotificationPalette = NO;
    self.gfLockRim.gfLightSurface = NO;
    [self gfRefreshBackdropBlurIfNeeded];
    [self gfRefreshBodyVeil];
    [self.gfLockRim setNeedsLayout];
}
- (void)gfRefreshBodyVeil {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (self.gfUsesNotificationPalette) {
        GFNotificationPalette palette = self.gfNotificationPalette;
        // Keep transmission stable while a card crosses the stack threshold.
        CGFloat opacity = palette.bodyOpacity;
        UIColor *body = [UIColor colorWithWhite:palette.bodyWhite alpha:opacity];
        self.gfBodyVeil.colors = @[(id)body.CGColor, (id)body.CGColor,
                                  (id)body.CGColor, (id)body.CGColor];
        self.gfBodyVeil.startPoint = CGPointMake(0.5, 0.0);
        self.gfBodyVeil.endPoint = CGPointMake(0.5, 1.0);
    } else if (self.gfLockRim.gfSubdued) {
        // A little neutral absorption separates exposed rear strips from the
        // wallpaper. No white fill or additive lift that can wash out a stack.
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:0.0 alpha:0.025].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.040].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.055].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.065].CGColor
        ];
        self.gfBodyVeil.startPoint = CGPointMake(0.5, 0.0);
        self.gfBodyVeil.endPoint = CGPointMake(0.5, 1.0);
    } else {
        self.gfBodyVeil.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.018].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.008].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.012].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.006].CGColor
        ];
        self.gfBodyVeil.startPoint = CGPointMake(0.3, 0.0);
        self.gfBodyVeil.endPoint = CGPointMake(0.7, 1.0);
    }
    // Circular controls retain their own recipe and native selected states.
    self.gfBodyVeil.hidden = self.gfCircular;
    [CATransaction commit];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.gfCircular) {
        self.layer.cornerCurve = kCACornerCurveCircular;
        self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    }
    self.gfLockRim.frame = self.bounds;
    self.gfLockRim.gfRadius = self.layer.cornerRadius;
    self.gfLockRim.gfCircular = self.gfCircular;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gfBodyVeil.frame = self.bounds;
    self.gfBodyVeil.hidden = self.gfCircular;
    [CATransaction commit];
    [self.gfLockRim setNeedsLayout];
}
@end

// Banners sample the current scene, with a capture group separate from lock
// screen cards. Their slide/scale animation must never classify them as rear cards.
@interface GFBannerGlassView : GFLockScreenGlassView
@end
@implementation GFBannerGlassView
- (NSString *)gfBackdropGroupName {
    return @"com.kulinich.glassfolders.notifications.banners";
}
@end

#import "GFNotificationGlassView.h"

// Small circular controls share the layered rim, but use a narrower shoulder
// and their own lighter backdrop. Selection and press feedback stay native.
@interface GFQuickActionGlassView : GFLockScreenGlassView
@end
@implementation GFQuickActionGlassView
- (instancetype)initWithStyle:(NSInteger)style strength:(CGFloat)strength {
    self = [super initWithStyle:style strength:strength];
    if (self) {
        self.gfCircular = YES;
        [self gfRefreshMaterial];
    }
    return self;
}
- (NSString *)gfBackdropGroupName {
    return @"com.kulinich.glassfolders.lock.buttons";
}
- (CGFloat)gfBackdropBlurRadius {
    return GFLockButtonBlurRadius * GFSharedGlassScale(GFGlassStrength);
}
- (void)gfRefreshBackdropBlurIfNeeded {
    [super gfRefreshBackdropBlurIfNeeded];
    CGFloat alpha = 0.18 * GFSharedGlassScale(GFGlassStrength);
    if (self.gfFallbackBlurView.alpha != alpha) self.gfFallbackBlurView.alpha = alpha;
}
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    self.gfTintView.alpha = GFUsesDarkAppearance(self) ? 0.045 : 0.028;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.gfBackdropSampleView.frame = CGRectInset(self.bounds, -12.0, -12.0);
    self.gfFallbackBlurView.frame = self.gfBackdropSampleView.frame;
}
@end

@interface GFLockBackgroundState : NSObject
@property (nonatomic, weak) UIView *background;
@property (nonatomic, strong) GFLockScreenGlassView *glass;
@property (nonatomic, assign) BOOL originalHidden;
@property (nonatomic, weak) UIView *stackOverlay;
@property (nonatomic, assign) BOOL originalStackOverlayHidden;
@property (nonatomic, strong) GFNotificationForegroundState *foreground;
- (void)restore;
@end
@implementation GFLockBackgroundState
- (void)restore {
    [self.foreground restore];
    self.foreground = nil;
    if (self.background) self.background.hidden = self.originalHidden;
    if (self.stackOverlay) self.stackOverlay.hidden = self.originalStackOverlayHidden;
    self.stackOverlay = nil;
    [self.glass removeFromSuperview];
    self.glass = nil;
    self.background = nil;
}
- (void)dealloc { [self restore]; }
@end

static char kGFLockBackgroundKey;
static char kGFLockPressKey;
static char kGFLockCoverSheetVisibleKey;
static char kGFLockCoverSheetDismissingKey;

static BOOL GFLockIsKind(id object, const char *name) {
    Class cls = objc_getClass(name);
    return cls && [object isKindOfClass:cls];
}

// Validate signatures before calling private getters. Never use KVC to search
// arbitrary view hierarchies, or assume MRUNowPlayingView owns a background.
static id GFLockObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), sel) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 || type[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}

static id GFLockIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static BOOL GFLockReadBool(id object, NSString *name, BOOL *value) {
    SEL sel = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), sel) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 ||
        (type[0] != 'B' && type[0] != 'c')) return NO;
    *value = ((BOOL (*)(id, SEL))objc_msgSend)(object, sel);
    return YES;
}

static BOOL GFLockBool(id object, NSString *name, BOOL fallback) {
    BOOL value = fallback;
    return GFLockReadBool(object, name, &value) ? value : fallback;
}

static CGFloat GFLockRadius(id object) {
    for (NSString *name in @[@"_continuousCornerRadius", @"_cornerRadius", @"cornerRadius"]) {
        SEL sel = NSSelectorFromString(name);
        Method method = object ? class_getInstanceMethod(object_getClass(object), sel) : NULL;
        char type[8] = {0};
        if (method) method_getReturnType(method, type, sizeof(type));
        if (method && method_getNumberOfArguments(method) == 2 && type[0] == 'd') {
            double radius = ((double (*)(id, SEL))objc_msgSend)(object, sel);
            if (isfinite(radius) && radius > 0.0) return radius;
        }
    }
    return 0.0;
}

static BOOL GFLockHasBoolArgumentMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    char result[8] = {0};
    char argument[8] = {0};
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, argument, sizeof(argument));
    return result[0] == 'v' && (argument[0] == 'B' || argument[0] == 'c');
}

static UIResponder *GFLockCoverSheetOwner(UIView *host) {
    UIResponder *responder = host;
    for (NSUInteger depth = 0; responder && depth < 64; depth++) {
        if (GFLockIsKind(responder, "CSCoverSheetViewController")) return responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL GFLockScreenDismissing(UIView *host) {
    return [objc_getAssociatedObject(GFLockCoverSheetOwner(host),
                                    &kGFLockCoverSheetDismissingKey) boolValue];
}

static BOOL GFLockScreenVisible(UIView *host) {
    // Authentication/manager flags may flip at the start of an interactive
    // dismissal, while the cover sheet is still on screen. Its appearance
    // lifetime lasts through that animation and through a cancelled swipe.
    // Scope the marker to the owning controller, not a global unlocked flag.
    NSNumber *visible = objc_getAssociatedObject(GFLockCoverSheetOwner(host),
                                                &kGFLockCoverSheetVisibleKey);
    if (visible) return visible.boolValue;
    // Fallback for unrecognized owners or lifecycle callbacks unavailable on
    // a particular OS. Banners have a separate gate and bypass this query.
    Class cls = objc_getClass("SBLockScreenManager");
    // Class methods use the metaclass, unlike the instance getter helper.
    SEL sel = NSSelectorFromString(@"sharedInstanceIfExists");
    Method method = cls ? class_getClassMethod(cls, sel) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 || type[0] != '@') return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)(cls, sel);
    // Face ID may unlock the device before the cover sheet is dismissed.
    return GFLockBool(manager, @"isLockScreenVisible", NO) ||
           GFLockBool(manager, @"isUILocked", NO);
}

static UIView *GFLockView(id object) {
    return [object isKindOfClass:UIView.class] ? object : nil;
}

static UIView *GFLockMaterial(id owner) {
    UIView *material = GFLockView(GFLockObject(owner, @"backgroundMaterialView"));
    if (material && (GFLockIsKind(material, "MTMaterialView") ||
                     [material isKindOfClass:UIVisualEffectView.class])) return material;
    // A platter's backgroundView is accepted only if it is itself a material.
    // Never suppress the platter: it can also own the card's content.
    UIView *background = GFLockView(GFLockObject(owner, @"backgroundView"));
    if (background && (GFLockIsKind(background, "MTMaterialView") ||
                       [background isKindOfClass:UIVisualEffectView.class])) return background;
    return nil;
}

static BOOL GFNotificationBannerPresentation(UIView *host, BOOL *banner) {
    // A short look can be attached before its private flag is updated. Prefer
    // an actual banner container; never infer banners merely from an unlocked
    // phone (Notification Center also uses short looks on the Home Screen).
    BOOL inBanner = NO;
    UIResponder *node = host;
    for (NSUInteger depth = 0; node && depth < 64; depth++, node = node.nextResponder) {
        if (GFLockIsKind(node, "NCNotificationLongLookView") ||
            GFLockIsKind(node, "NCNotificationLongLookViewController")) return NO;
        if (GFLockIsKind(node, "SBBannerContainerView") ||
            GFLockIsKind(node, "SBNotificationBannerWindow") ||
            GFLockIsKind(node, "SBBannerWindow") ||
            GFLockIsKind(node, "BNBannerWindow") ||
            GFLockIsKind(node, "BNBannerViewController") ||
            GFLockIsKind(node, "NCNotificationBannerViewController")) inBanner = YES;
    }
    if (inBanner) { *banner = YES; return YES; }
    if (GFLockCoverSheetOwner(host)) { *banner = NO; return YES; }
    return GFLockReadBool(host, @"_isBanner", banner) ||
           GFLockReadBool(host, @"isBanner", banner);
}

static UIView *GFNotificationMaterial(UIView *host, UIView *content) {
    UIView *material = GFLockMaterial(host);
    if (material) return material;
    // Some presentations wrap the material in a dedicated background shell.
    // Search only that explicit branch, never the text/remote-content tree.
    UIView *shell = GFLockView(GFLockObject(host, @"backgroundView"));
    if (!shell) shell = GFLockView(GFLockIvar(host, "_backgroundView"));
    if (!shell || shell == host || ![shell isDescendantOfView:host] ||
        !content || [content isDescendantOfView:shell] ||
        [shell isDescendantOfView:content]) return nil;
    NSArray<UIView *> *level = @[shell];
    UIView *found = nil;
    for (NSUInteger depth = 0; depth < 4 && level.count; depth++) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *view in level) {
            if ([view isKindOfClass:GFLockScreenGlassView.class]) continue;
            if (GFLockIsKind(view, "MTMaterialView") ||
                [view isKindOfClass:UIVisualEffectView.class]) {
                // Multiple independent materials are ambiguous: stay native.
                if (found && found != view) return nil;
                found = view;
            } else {
                [next addObjectsFromArray:view.subviews];
            }
        }
        level = next;
    }
    return found;
}

static void GFUpdateNotificationContainer(UIView *container) {
    // The wrapper lays out after its short look, and may assign the background
    // or banner context there. Refresh only its identified notification child.
    UIView *content = GFLockView(GFLockObject(container, @"contentView"));
    if (!content) content = GFLockView(GFLockIvar(container, "_contentView"));
    if (GFLockIsKind(content, "NCNotificationShortLookView") &&
        [content isDescendantOfView:container]) GFUpdateLockScreenSurface(content);
}

static void GFRestoreLockScreenSurface(UIView *host) {
    GFLockBackgroundState *state = objc_getAssociatedObject(host, &kGFLockBackgroundKey);
    [state restore];
    objc_setAssociatedObject(host, &kGFLockBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL GFLockNotificationIsStacked(UIView *host) {
    // Swipe, bounce and dismissal also scale front cards. Only the native
    // content-hidden state identifies a rear strip; unknown layouts stay front.
    return GFLockBool(host, @"isNotificationContentViewHidden", NO);
}

static void GFLockSyncStackOverlay(UIView *host, GFLockBackgroundState *state) {
    // Apple's separate stacking overlay is tuned for an opaque system
    // platter. Retaining it over transparent glass can add a bright rear slab.
    // Suppress only this known decorative view while our replacement exists.
    UIView *overlay = GFLockView(GFLockIvar(host, "_stackDimmingOverlayView"));
    if (!GFLockIsKind(overlay, "NCNotificationListStackDimmingOverlayView") ||
        ![overlay isDescendantOfView:host]) overlay = nil;
    if (state.stackOverlay != overlay) {
        if (state.stackOverlay) state.stackOverlay.hidden = state.originalStackOverlayHidden;
        state.stackOverlay = overlay;
        state.originalStackOverlayHidden = overlay.hidden;
    }
    if (overlay) overlay.hidden = YES;
}

static void GFUpdateLockScreenSurface(UIView *host) {
    if (!host || GFNotificationUpdatingForeground) return;
    GFLockBackgroundState *state = objc_getAssociatedObject(host, &kGFLockBackgroundKey);
    if (!state && !GFBannerNotificationsEnabled && !GFLockNotificationsEnabled && !GFLockQuickActionsEnabled &&
        !GFLockMusicEnabled && !GFLockActivitiesEnabled) return;

    BOOL enabled = NO;
    BOOL circle = NO;
    BOOL notification = GFLockIsKind(host, "NCNotificationShortLookView");
    BOOL banner = NO;
    UIView *background = nil;
    UIView *content = nil;
    id radiusOwner = host;
    if (notification) {
        BOOL knownPresentation = GFNotificationBannerPresentation(host, &banner);
        enabled = knownPresentation && (banner ? GFBannerNotificationsEnabled : GFLockNotificationsEnabled);
        content = GFLockView(GFLockObject(host, @"_notificationContentView"));
        if (!content) content = GFLockView(GFLockObject(host, @"notificationContentView"));
        if (!content) content = GFLockView(GFLockIvar(host, "_notificationContentView"));
        background = GFNotificationMaterial(host, content);
    } else if (GFLockIsKind(host, "CSQuickActionsButton")) {
        circle = YES;
        UIControl *button = (UIControl *)host;
        // Latching/pronounced describe button configuration, not whether the
        // flashlight is currently on. Use selection and actual press state.
        enabled = GFLockQuickActionsEnabled && !button.selected && !button.highlighted &&
                  (button.enabled || GFLockScreenDismissing(host)) &&
                  ![objc_getAssociatedObject(host, &kGFLockPressKey) boolValue];
        background = GFLockView(GFLockIvar(host, "_backgroundEffectView"));
        if (![background isKindOfClass:UIVisualEffectView.class]) background = nil;
        content = GFLockView(GFLockIvar(host, "_contentView"));
    } else if (GFLockIsKind(host, "CSAdjunctItemView")) {
        id contentHost = GFLockObject(host, @"contentHost");
        enabled = GFLockMusicEnabled && GFLockIsKind(contentHost, "CSMediaControlsViewController");
        radiusOwner = GFLockObject(host, @"platterView");
        background = GFLockMaterial(radiusOwner);
        if ([contentHost isKindOfClass:UIViewController.class])
            content = ((UIViewController *)contentHost).viewIfLoaded;
    } else if (GFLockIsKind(host, "NCNotificationListSupplementaryHostingView")) {
        // Only Live Activities, never arbitrary supplementary cards. The
        // hosting controller identifies its child without loading its view.
        id delegate = GFLockObject(host, @"delegate");
        id contentHost = GFLockObject(delegate, @"hostedViewController");
        enabled = GFLockActivitiesEnabled && GFLockIsKind(contentHost, "CSActivityItemViewController");
        content = GFLockView(GFLockObject(host, @"hostedView"));
        radiusOwner = GFLockObject(host, @"platterView");
        background = GFLockMaterial(radiusOwner);
    }

    // Unknown/missing background layouts are left untouched. In particular,
    // an opaque remotely rendered Live Activity is never made transparent.
    if (!enabled || !host.window || (!banner && !GFLockScreenVisible(host)) || !background ||
        background == host || ![background isDescendantOfView:host] ||
        !content || ![content isDescendantOfView:host] || [content isDescendantOfView:background]) {
        if (state) GFRestoreLockScreenSurface(host);
        return;
    }
    if (background.bounds.size.width <= 0.0 || background.bounds.size.height <= 0.0) {
        // Native layout can pass through empty bounds during stack animation.
        // Hide that frame, retaining the material instead of flashing native
        // blur and rebuilding our capture group on the following layout.
        if (state && notification && !banner && state.background == background) {
            state.glass.hidden = YES;
        } else if (state) {
            GFRestoreLockScreenSurface(host);
        }
        return;
    }
    BOOL homeBanner = notification && banner && GFHomeScreenVisible();
    BOOL adaptiveNotification = notification && (!banner || homeBanner);
    GFNotificationPalette palette = {0};
    GFNotificationForegroundState *foreground = state.foreground;
    if (adaptiveNotification) {
        if (!foreground) foreground = [GFNotificationForegroundState new];
        palette = homeBanner ? [foreground paletteForHomeBannerHost:host] :
                               [foreground paletteForHost:host];
        if (!palette.valid || UIAccessibilityIsReduceTransparencyEnabled() ||
            UIAccessibilityDarkerSystemColorsEnabled()) {
            if (state) GFRestoreLockScreenSurface(host);
            return;
        }
    }
    Class glassClass = circle ? GFQuickActionGlassView.class :
        (banner ? GFBannerGlassView.class :
         (notification ? GFNotificationGlassView.class : GFLockScreenGlassView.class));
    if (state && (state.background != background || ![state.glass isMemberOfClass:glassClass])) {
        GFRestoreLockScreenSurface(host);
        state = nil;
    }
    if (!state) {
        state = [GFLockBackgroundState new];
        state.background = background;
        state.originalHidden = background.hidden;
        state.glass = [[glassClass alloc] initWithStyle:1 strength:0.55];
        state.glass.isAccessibilityElement = NO;
        state.glass.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(host, &kGFLockBackgroundKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *container = background.superview;
    GFLockScreenGlassView *glass = state.glass;
    if (banner && !homeBanner && state.foreground) {
        [state.foreground restore];
        state.foreground = nil;
        [glass gfClearNotificationPalette];
    }
    if (adaptiveNotification) {
        state.foreground = foreground;
        [glass gfApplyNotificationPalette:palette];
        NSUInteger textCount = [foreground applyToHost:host content:content];
        BOOL contentHidden = GFLockBool(host, @"isNotificationContentViewHidden", NO);
        if (!textCount && !contentHidden) {
            GFRestoreLockScreenSurface(host);
            return;
        }
    }
    // One strength change also reaches retained music/activity/button surfaces.
    [glass gfRefreshBackdropBlurIfNeeded];
    // UIKit may initially hide a banner material until presentation finishes.
    // Observe a subsequent native reveal instead of freezing that initial
    // hidden state for the entire lifetime of the replacement.
    if (!background.hidden) state.originalHidden = NO;
    if (notification && !banner) {
        ((GFNotificationGlassView *)glass).gfStacked = GFLockNotificationIsStacked(host);
        GFLockSyncStackOverlay(host, state);
    }
    NSUInteger index = [container.subviews indexOfObjectIdenticalTo:background];
    if (glass.superview != container ||
        [container.subviews indexOfObjectIdenticalTo:glass] != index + 1)
        [container insertSubview:glass aboveSubview:background];
    CGRect bounds = (CGRect){CGPointZero, background.bounds.size};
    if (!CGRectEqualToRect(glass.bounds, bounds)) glass.bounds = bounds;
    if (!CGPointEqualToPoint(glass.center, background.center)) glass.center = background.center;
    if (!CGAffineTransformEqualToTransform(glass.transform, background.transform))
        glass.transform = background.transform;
    if (glass.alpha != background.alpha) glass.alpha = background.alpha;
    if (glass.hidden != state.originalHidden) glass.hidden = state.originalHidden;
    if (glass.layer.zPosition != background.layer.zPosition)
        glass.layer.zPosition = background.layer.zPosition;
    CGFloat radius = circle ? MIN(background.bounds.size.width, background.bounds.size.height) * 0.5 :
                             GFLockRadius(radiusOwner);
    if (radius <= 0.0) radius = background.layer.cornerRadius;
    if (radius <= 0.0) radius = MIN(24.0, background.bounds.size.height * 0.5);
    glass.gfCircular = circle;
    [glass setPreferredRadius:radius];
    if (!background.hidden) background.hidden = YES;
}

static void GFRefreshNotificationTextOwner(UIView *content) {
    if (GFNotificationUpdatingForeground) return;
    UIView *node = content;
    for (NSUInteger depth = 0; node && depth < 12; depth++, node = node.superview) {
        if (GFLockIsKind(node, "NCNotificationShortLookView")) {
            // Child-only layout/style changes can occur without platter layout.
            GFLockBackgroundState *state = objc_getAssociatedObject(node, &kGFLockBackgroundKey);
            if (state.foreground) {
                UIView *body = GFLockView(GFLockObject(node, @"_notificationContentView"));
                if (!body) body = GFLockView(GFLockIvar(node, "_notificationContentView"));
                if (body) [state.foreground applyToHost:node content:body];
            }
            return;
        }
    }
}

// One event-driven pass after lock-screen presentation/state changes. No
// preference I/O, signature verification, timer or per-frame tree traversal.
static void GFLockScheduleRefresh(void) {
    static BOOL queued = NO;
    if (queued) return;
    queued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        queued = NO;
        GFLiveRefreshAllSurfaces();
    });
}
#endif
