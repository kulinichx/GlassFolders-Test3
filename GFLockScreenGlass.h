// Included after GFPanelGlassView. Only known system material backgrounds are
// replaced; notification content, remote activity scenes and controls stay intact.
#ifndef GF_LOCK_SCREEN_GLASS_H
#define GF_LOCK_SCREEN_GLASS_H

@interface GFLockScreenGlassView : GFPanelGlassView
@property (nonatomic, assign) BOOL gfCircular;
@end
@implementation GFLockScreenGlassView
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.gfCircular) self.layer.cornerCurve = kCACornerCurveCircular;
}
@end

@interface GFLockBackgroundState : NSObject
@property (nonatomic, weak) UIView *background;
@property (nonatomic, strong) GFLockScreenGlassView *glass;
@property (nonatomic, assign) BOOL originalHidden;
- (void)restore;
@end
@implementation GFLockBackgroundState
- (void)restore {
    if (self.background) self.background.hidden = self.originalHidden;
    [self.glass removeFromSuperview];
    self.glass = nil;
    self.background = nil;
}
- (void)dealloc { [self restore]; }
@end

static char kGFLockBackgroundKey;
static char kGFLockPressKey;

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

static BOOL GFLockBool(id object, NSString *name, BOOL fallback) {
    SEL sel = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod(object_getClass(object), sel) : NULL;
    char type[8] = {0};
    if (method) method_getReturnType(method, type, sizeof(type));
    if (!method || method_getNumberOfArguments(method) != 2 ||
        (type[0] != 'B' && type[0] != 'c')) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, sel);
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

static BOOL GFLockScreenVisible(void) {
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

static void GFRestoreLockScreenSurface(UIView *host) {
    GFLockBackgroundState *state = objc_getAssociatedObject(host, &kGFLockBackgroundKey);
    [state restore];
    objc_setAssociatedObject(host, &kGFLockBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void GFUpdateLockScreenSurface(UIView *host) {
    if (!host) return;
    GFLockBackgroundState *state = objc_getAssociatedObject(host, &kGFLockBackgroundKey);
    if (!state && !GFLockNotificationsEnabled && !GFLockQuickActionsEnabled &&
        !GFLockMusicEnabled && !GFLockActivitiesEnabled) return;

    BOOL enabled = NO;
    BOOL circle = NO;
    UIView *background = nil;
    UIView *content = nil;
    id radiusOwner = host;
    if (GFLockIsKind(host, "NCNotificationShortLookView")) {
        enabled = GFLockNotificationsEnabled && !GFLockBool(host, @"_isBanner", YES);
        background = GFLockMaterial(host);
        content = GFLockView(GFLockObject(host, @"notificationContentView"));
        if (!content) content = GFLockView(GFLockIvar(host, "_notificationContentView"));
    } else if (GFLockIsKind(host, "CSQuickActionsButton")) {
        circle = YES;
        UIControl *button = (UIControl *)host;
        enabled = GFLockQuickActionsEnabled && !button.selected && !button.highlighted &&
                  button.enabled && !GFLockBool(host, @"isLatching", NO) &&
                  !GFLockBool(host, @"isPronounced", NO) &&
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
    if (!enabled || !host.window || !GFLockScreenVisible() || !background ||
        background == host || ![background isDescendantOfView:host] ||
        !content || ![content isDescendantOfView:host] || [content isDescendantOfView:background] ||
        background.bounds.size.width <= 0.0 || background.bounds.size.height <= 0.0) {
        if (state) GFRestoreLockScreenSurface(host);
        return;
    }
    if (state && state.background != background) {
        GFRestoreLockScreenSurface(host);
        state = nil;
    }
    if (!state) {
        state = [GFLockBackgroundState new];
        state.background = background;
        state.originalHidden = background.hidden;
        state.glass = [[GFLockScreenGlassView alloc] initWithStyle:1 strength:0.55];
        state.glass.isAccessibilityElement = NO;
        state.glass.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(host, &kGFLockBackgroundKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *container = background.superview;
    GFLockScreenGlassView *glass = state.glass;
    NSUInteger index = [container.subviews indexOfObjectIdenticalTo:background];
    if (glass.superview != container ||
        [container.subviews indexOfObjectIdenticalTo:glass] != index + 1)
        [container insertSubview:glass aboveSubview:background];
    glass.bounds = (CGRect){CGPointZero, background.bounds.size};
    glass.center = background.center;
    glass.transform = background.transform;
    glass.alpha = background.alpha;
    glass.hidden = state.originalHidden;
    glass.layer.zPosition = background.layer.zPosition;
    CGFloat radius = circle ? MIN(background.bounds.size.width, background.bounds.size.height) * 0.5 :
                             GFLockRadius(radiusOwner);
    if (radius <= 0.0) radius = background.layer.cornerRadius;
    if (radius <= 0.0) radius = MIN(24.0, background.bounds.size.height * 0.5);
    glass.gfCircular = circle;
    [glass setPreferredRadius:radius];
    if (!background.hidden) background.hidden = YES;
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
