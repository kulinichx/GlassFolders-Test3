// Included after GFPanelGlassView. Only known system material backgrounds are
// replaced; notification content, remote activity scenes and controls stay intact.
#ifndef GF_LOCK_SCREEN_GLASS_H
#define GF_LOCK_SCREEN_GLASS_H

static CGFloat GFLockBlurStrength(void) {
    return isfinite(GFGlassStrength) ? GFClamp01(GFGlassStrength) : 0.55;
}

static CGFloat GFLockBlurRadius(CGFloat strength) {
    // Preserve lock2's 6 pt card / 3 pt button baseline at the existing 55%.
    // Higher values add diffusion, never additive luminance or stronger rims.
    return strength <= 0.55 ? 6.0 * strength / 0.55 :
        6.0 + 12.0 * (strength - 0.55) / 0.45;
}

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
        if (blur) {
            [blur setValue:@(radius) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [filters addObject:blur];
        }
        // No additive brightness filter: it can accumulate across a stack.
        [backdrop setValue:filters forKey:@"filters"];
        glass.gfBackdropSampleView.alpha = 1.0;
    }
}

@interface GFLockScreenGlassView : GFPanelGlassView
@property (nonatomic, assign) BOOL gfCircular;
@property (nonatomic, assign) CGFloat gfAppliedBlurStrength;
@end
@implementation GFLockScreenGlassView
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    self.gfAppliedBlurStrength = GFLockBlurStrength();
    GFLockApplyBackdropRecipe(self, @"com.kulinich.glassfolders.lock.cards",
                             GFLockBlurRadius(self.gfAppliedBlurStrength));
    if (self.gfFallbackBlurView) {
        self.gfFallbackBlurView.effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        self.gfFallbackBlurView.alpha = 0.40 * self.gfAppliedBlurStrength;
    }
    // Keep the body neutral; directional lighting belongs at the edge, not
    // in a white fill that becomes brighter with every overlapping card.
    self.gfTintView.alpha = 0.0;
    self.gfOpticalLayer.opacity = 0.65;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.gfCircular) self.layer.cornerCurve = kCACornerCurveCircular;
}
@end

// Rear cards expose only a narrow strip. Reusing the large panel's optical
// rail there turns that strip into a bright slab on light wallpapers.
@interface GFNotificationGlassView : GFLockScreenGlassView
@property (nonatomic, assign) BOOL gfStacked;
@end
@implementation GFNotificationGlassView
- (void)setGfStacked:(BOOL)stacked {
    if (_gfStacked == stacked) return;
    _gfStacked = stacked;
    [self gfRefreshMaterial];
}
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    self.gfOpticalLayer.hidden = self.gfStacked;
    if (self.gfStacked) {
        // A single subdued outline, with no filled optical shoulder.
        self.layer.borderWidth = 0.35;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
    }
}
@end

// A 50 pt circular control needs its own material and specular geometry. The
// large-card optical texture is too soft/dense at this scale and is generated
// for continuous rounded rectangles, rather than a circular button.
@interface GFQuickActionGlassView : GFLockScreenGlassView
@property (nonatomic, strong) CAGradientLayer *gfCircularRim;
@property (nonatomic, strong) CAShapeLayer *gfCircularRimMask;
@property (nonatomic, assign) CGSize gfCircularRimSize;
@end
@implementation GFQuickActionGlassView
- (instancetype)initWithStyle:(NSInteger)style strength:(CGFloat)strength {
    self = [super initWithStyle:style strength:strength];
    if (self) {
        self.gfCircular = YES;
        self.gfCircularRim = [CAGradientLayer layer];
        self.gfCircularRim.startPoint = CGPointMake(0.15, 0.0);
        self.gfCircularRim.endPoint = CGPointMake(0.85, 1.0);
        self.gfCircularRim.locations = @[@0.0, @0.28, @0.60, @1.0];
        self.gfCircularRim.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.42].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.035].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor
        ];
        self.gfCircularRim.zPosition = 21.0;
        self.gfCircularRim.contentsScale = UIScreen.mainScreen.scale;
        self.gfCircularRimMask = [CAShapeLayer layer];
        self.gfCircularRimMask.contentsScale = UIScreen.mainScreen.scale;
        self.gfCircularRimMask.fillColor = UIColor.clearColor.CGColor;
        self.gfCircularRimMask.strokeColor = UIColor.whiteColor.CGColor;
        self.gfCircularRimMask.lineWidth = 0.7;
        self.gfCircularRim.mask = self.gfCircularRimMask;
        [self.layer addSublayer:self.gfCircularRim];
    }
    return self;
}
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    // Keep wallpaper detail at button scale, with a small neutral lift. No
    // opaque grey disc, copied wallpaper image, or overlay over the icon.
    GFLockApplyBackdropRecipe(self, @"com.kulinich.glassfolders.lock.buttons",
                             0.5 * GFLockBlurRadius(self.gfAppliedBlurStrength));
    if (self.gfFallbackBlurView) {
        self.gfFallbackBlurView.effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        self.gfFallbackBlurView.alpha = (0.18 / 0.55) * self.gfAppliedBlurStrength;
    }
    self.gfTintView.alpha = GFUsesDarkAppearance(self) ? 0.045 : 0.028;
    self.layer.borderWidth = 0.0;
    self.gfOpticalLayer.hidden = YES;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // The rounded-card texture stays unused. The mask and highlight both use
    // the same exact ellipse, including when display zoom changes the size.
    self.gfOpticalLayer.hidden = YES;
    self.layer.cornerCurve = kCACornerCurveCircular;
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    self.gfBackdropSampleView.frame = CGRectInset(self.bounds, -12.0, -12.0);
    self.gfFallbackBlurView.frame = self.gfBackdropSampleView.frame;
    if (!CGSizeEqualToSize(self.gfCircularRimSize, self.bounds.size)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.gfCircularRim.frame = self.bounds;
        self.gfCircularRimMask.frame = self.bounds;
        CGRect ring = CGRectInset(self.bounds, 0.5, 0.5);
        self.gfCircularRimMask.path = [UIBezierPath bezierPathWithOvalInRect:ring].CGPath;
        self.gfCircularRimSize = self.bounds.size;
        [CATransaction commit];
    }
}
@end

@interface GFLockBackgroundState : NSObject
@property (nonatomic, weak) UIView *background;
@property (nonatomic, strong) GFLockScreenGlassView *glass;
@property (nonatomic, assign) BOOL originalHidden;
@property (nonatomic, weak) UIView *stackOverlay;
@property (nonatomic, assign) BOOL originalStackOverlayHidden;
- (void)restore;
@end
@implementation GFLockBackgroundState
- (void)restore {
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
static char kGFLockStackedKey;

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

static BOOL GFLockTransformIsStacked(CGAffineTransform transform) {
    CGFloat scaleX = hypot(transform.a, transform.b);
    CGFloat scaleY = hypot(transform.c, transform.d);
    return isfinite(scaleX) && isfinite(scaleY) &&
           (scaleX < 0.999 || scaleY < 0.999);
}

static BOOL GFLockNotificationIsStacked(UIView *host) {
    if ([objc_getAssociatedObject(host, &kGFLockStackedKey) boolValue] ||
        GFLockBool(host, @"isNotificationContentViewHidden", NO)) return YES;
    // Initial/reused views may be laid out before the dimming callback. Check
    // only this card's wrappers, stopping before the list's own transform.
    UIView *node = host;
    for (NSUInteger depth = 0; node && depth < 8; depth++, node = node.superview) {
        if (GFLockIsKind(node, "NCNotificationListView")) break;
        if (GFLockTransformIsStacked(node.transform)) return YES;
        if (GFLockIsKind(node, "NCNotificationListCell")) break;
    }
    return NO;
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
    if (!host) return;
    GFLockBackgroundState *state = objc_getAssociatedObject(host, &kGFLockBackgroundKey);
    if (!state && !GFLockNotificationsEnabled && !GFLockQuickActionsEnabled &&
        !GFLockMusicEnabled && !GFLockActivitiesEnabled) return;

    BOOL enabled = NO;
    BOOL circle = NO;
    BOOL notification = GFLockIsKind(host, "NCNotificationShortLookView");
    UIView *background = nil;
    UIView *content = nil;
    id radiusOwner = host;
    if (notification) {
        enabled = GFLockNotificationsEnabled && !GFLockBool(host, @"_isBanner", YES);
        background = GFLockMaterial(host);
        content = GFLockView(GFLockObject(host, @"notificationContentView"));
        if (!content) content = GFLockView(GFLockIvar(host, "_notificationContentView"));
    } else if (GFLockIsKind(host, "CSQuickActionsButton")) {
        circle = YES;
        UIControl *button = (UIControl *)host;
        // Latching/pronounced describe button configuration, not whether the
        // flashlight is currently on. Use selection and actual press state.
        enabled = GFLockQuickActionsEnabled && !button.selected && !button.highlighted &&
                  button.enabled &&
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
        Class glassClass = circle ? GFQuickActionGlassView.class :
            (notification ? GFNotificationGlassView.class : GFLockScreenGlassView.class);
        state.glass = [[glassClass alloc] initWithStyle:1 strength:0.55];
        state.glass.isAccessibilityElement = NO;
        state.glass.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(host, &kGFLockBackgroundKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *container = background.superview;
    GFLockScreenGlassView *glass = state.glass;
    if (fabs(glass.gfAppliedBlurStrength - GFLockBlurStrength()) > 0.0001)
        [glass gfRefreshMaterial];
    if (notification) {
        ((GFNotificationGlassView *)glass).gfStacked = GFLockNotificationIsStacked(host);
        GFLockSyncStackOverlay(host, state);
    }
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
