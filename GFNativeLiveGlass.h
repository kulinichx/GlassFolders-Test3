#ifndef GF_NATIVE_LIVE_GLASS_H
#define GF_NATIVE_LIVE_GLASS_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// GlassFolders: live compositor-backed glass bridge.
// No screenshots, UIImageView, Core Image snapshot or persistent images.
// This never changes native material visibility or intercepts touches.
// A refractive shader must be registered with CARenderServer by a compatible
// provider; CABackdropLayer alone does NOT create physical refraction.
static BOOL GFNativeLiveGlassEnabled = NO;

@interface GFNativeLiveGlassOverlay : UIView
@property (nonatomic, strong) UIView *provider;
@property (nonatomic, assign) BOOL verified;
@property (nonatomic, assign) CGFloat gfPreferredRadius;
@property (nonatomic, assign) CGRect gfLastMaskedBounds;
@property (nonatomic, assign) CGFloat gfLastMaskedRadius;
@end
@implementation GFNativeLiveGlassOverlay
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.provider) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.provider.frame = self.bounds;
    CGFloat shortest = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat radius = (self.gfPreferredRadius > 0.0)
        ? MIN(self.gfPreferredRadius, shortest * 0.50)
        : MIN(24.0, shortest * 0.14); // unchanged App Library default
    self.layer.cornerRadius = radius;
    self.provider.layer.cornerRadius = radius;
    self.provider.layer.masksToBounds = YES;
    if (CGRectEqualToRect(self.gfLastMaskedBounds, self.bounds) &&
        fabs(self.gfLastMaskedRadius - radius) < 0.25 && self.layer.mask) {
        [CATransaction commit];
        return;
    }
    // Keep the optical test confined to the rim, not the card interior.
    CGFloat inset = self.gfPreferredRadius > 0.0
        ? MIN(12.0, shortest * 0.11) : 15.0;
    CGRect outerRect = self.bounds;
    CGRect innerRect = CGRectInset(outerRect, inset, inset);
    CGFloat innerRadius = MAX(0.0, radius - inset);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:outerRect
                                                     cornerRadius:radius];
    [shape appendPath:[UIBezierPath bezierPathWithRoundedRect:innerRect
                                                cornerRadius:innerRadius]];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = outerRect;
    mask.path = shape.CGPath;
    mask.fillRule = kCAFillRuleEvenOdd;
    self.layer.mask = mask;
    self.gfLastMaskedBounds = outerRect;
    self.gfLastMaskedRadius = radius;
    [CATransaction commit];
}
@end

// GlassFolders-owned backdrop host. Unlike v7, this does not need the
// LGLiveBackdropView Objective-C class. It still requires a renderer-registered
// *custom refractive CAFilter*; QuartzCore does not register one for us.
// This does not snapshot, alter, hide, or recolor the stock material.
@interface GFNativeDirectBackdropView : UIView
@property (nonatomic, copy) NSString *gfRefractiveType;
@property (nonatomic, assign) BOOL gfFilterAttached;
- (void)gfApplyFilterIfPossible;
@end

static id GFNativeRegisteredFilter(NSString *type) {
    Class cls = NSClassFromString(@"CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithType:");
    if (!cls || ![cls respondsToSelector:factory]) return nil;
    @try {
        id filter = ((id (*)(Class, SEL, id))objc_msgSend)(cls, factory, type);
        if (!filter) return nil;
        // Do not accept a generic blur substituted for a custom refraction.
        NSString *reported = [filter valueForKey:@"type"];
        if (![reported isKindOfClass:[NSString class]] ||
            ![reported isEqualToString:type]) return nil;
        return filter;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *GFNativeAvailableFilterType(void) {
    // Do not cache a failure: renderer registration can finish after launch.
    for (NSString *type in @[@"dylv.liquidglass.refraction",
                            @"dylv.liquidglass.dock"]) {
        if (GFNativeRegisteredFilter(type)) return type;
    }
    return nil;
}

@implementation GFNativeDirectBackdropView
+ (Class)layerClass {
    Class layerType = NSClassFromString(@"CABackdropLayer");
    return layerType ?: [CALayer class];
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.layer.masksToBounds = YES;
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self gfApplyFilterIfPossible];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.window && !self.gfFilterAttached)
        [self gfApplyFilterIfPossible];
}
- (void)gfApplyFilterIfPossible {
    if (!self.window || !self.gfRefractiveType.length) return;
    Class cls = NSClassFromString(@"CABackdropLayer");
    if (!cls || ![self.layer isKindOfClass:cls]) return;
    if (self.gfFilterAttached) return;
    id filter = GFNativeRegisteredFilter(self.gfRefractiveType);
    if (!filter) return;
    // iOS private KVC keys vary by firmware: best effort, never block the
    // actual registered CAFilter merely because an optional flag is missing.
    @try { [self.layer setValue:@NO forKey:@"layerUsesCoreImageFilters"]; }
    @catch (__unused NSException *e) {}
    @try { [self.layer setValue:@YES forKey:@"windowServerAware"]; }
    @catch (__unused NSException *e) {}
    @try {
        self.layer.filters = @[filter];
        id installed = self.layer.filters.firstObject;
        NSString *actualType = [installed valueForKey:@"type"];
        self.gfFilterAttached = [actualType isEqualToString:self.gfRefractiveType];
        if (!self.gfFilterAttached) self.layer.filters = nil;
    } @catch (__unused NSException *e) {
        self.gfFilterAttached = NO;
        self.layer.filters = nil;
    }
}
@end

// Preferred: use a separately installed, already-loaded live compositor
// provider if one is available. We do not bundle or copy its implementation.
static UIView *GFNativeLiveVendorView(CGRect frame) {
    // Prefer our own system backdrop host when a registered refractive filter
    // is visible. Fall back to the v7 compatibility adapter otherwise.
    NSString *filterType = GFNativeAvailableFilterType();
    if (filterType && NSClassFromString(@"CABackdropLayer")) {
        GFNativeDirectBackdropView *native =
            [[GFNativeDirectBackdropView alloc] initWithFrame:frame];
        native.gfRefractiveType = filterType;
        return native;
    }
    Class cls = NSClassFromString(@"LGLiveBackdropView");
    SEL initializer = NSSelectorFromString(@"initWithFrame:groupName:filterType:");
    SEL verified = NSSelectorFromString(@"lgFilterAttached");
    if (!cls || ![cls instancesRespondToSelector:initializer] ||
        ![cls instancesRespondToSelector:verified]) return nil;
    id object = nil;
    @try {
        // This is a known registered host family in LiqLite 0.2, not a claim
        // that App Library itself is an officially registered host.
        object = ((id (*)(id, SEL, CGRect, id, id))objc_msgSend)(
            [cls alloc], initializer, frame, nil, @"dylv.liquidglass.dock");
        if (![object isKindOfClass:[UIView class]]) return nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
    return (UIView *)object;
}

static BOOL GFNativeLiveVendorAttached(UIView *view) {
    if ([view isKindOfClass:[GFNativeDirectBackdropView class]]) {
        GFNativeDirectBackdropView *native = (GFNativeDirectBackdropView *)view;
        [native gfApplyFilterIfPossible];
        return native.gfFilterAttached;
    }
    SEL query = NSSelectorFromString(@"lgFilterAttached");
    if (!view || ![view respondsToSelector:query]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(view, query);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void GFNativeLiveCollect(UIView *v,
                                NSMutableArray<UIView *> *result,
                                NSUInteger *visited) {
    if (!v || *visited >= 3000 || result.count >= 64) return;
    ++(*visited);
    Class glassClass = NSClassFromString(@"GFAppLibraryGlassView");
    if (glassClass && [v isKindOfClass:glassClass]) {
        CGSize s = v.bounds.size;
        if (v.window && !v.hidden && s.width >= 115 && s.height >= 110 &&
            s.width < 600 && s.height < 550) [result addObject:v];
        return;
    }
    for (UIView *child in [v.subviews copy]) {
        GFNativeLiveCollect(child, result, visited);
        if (*visited >= 3000 || result.count >= 64) break;
    }
}

static void GFNativeLiveInstall(UIView *root, BOOL enabled) {
    if (![NSThread isMainThread] || !root) return;
    NSMutableArray<UIView *> *cards = [NSMutableArray array];
    NSUInteger count = 0;
    GFNativeLiveCollect(root, cards, &count);
    if (!cards.count) return;
    [cards sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGRect x = [a convertRect:a.bounds toView:a.window];
        CGRect y = [b convertRect:b.bounds toView:b.window];
        if (fabs(x.origin.y-y.origin.y) > 20.0)
            return x.origin.y < y.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return x.origin.x < y.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];

    // Remove stale / disabled overlays first. Never hide the stock host.
    UIView *selected = enabled ? cards.firstObject : nil;
    for (UIView *card in cards) {
        for (UIView *sub in [card.subviews copy]) {
            if ([sub isKindOfClass:[GFNativeLiveGlassOverlay class]] &&
                (card != selected || !enabled)) [sub removeFromSuperview];
        }
    }
    if (!enabled || !selected || !selected.window) return;
    for (UIView *sub in selected.subviews)
        if ([sub isKindOfClass:[GFNativeLiveGlassOverlay class]]) return;

    GFNativeLiveGlassOverlay *overlay = [[GFNativeLiveGlassOverlay alloc]
        initWithFrame:selected.bounds];
    overlay.userInteractionEnabled = NO;
    overlay.opaque = NO;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.clipsToBounds = YES;
    overlay.hidden = YES; // no visible overlay without a verified live filter
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                               UIViewAutoresizingFlexibleHeight;

    UIView *provider = GFNativeLiveVendorView(overlay.bounds);
    if (!provider) return;
    provider.userInteractionEnabled = NO;
    provider.opaque = NO;
    provider.backgroundColor = UIColor.clearColor;
    provider.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;
    overlay.provider = provider;
    [overlay addSubview:provider];
    [selected addSubview:overlay];
    [overlay setNeedsLayout];
    [overlay layoutIfNeeded];

    // Check twice because the render-server shader registry may be ready
    // after the view first enters SpringBoard's window. Time-bounded.
    __weak GFNativeLiveGlassOverlay *weakOverlay = overlay;
    for (NSNumber *delay in @[@0.8, @2.8]) {
        BOOL finalAttempt = (delay.doubleValue > 2.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                       (int64_t)(delay.doubleValue*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            GFNativeLiveGlassOverlay *lens = weakOverlay;
            if (!lens || !lens.window || lens.verified) return;
            if (GFNativeLiveVendorAttached(lens.provider)) {
                lens.verified = YES;
                lens.hidden = NO;
            } else if (finalAttempt) {
                [lens removeFromSuperview];
            }
        });
    }
}


// Optics Lab 03: a narrow, opt-in bridge for the user's OWN folder glass.
// It does not register or ship a CA render-server shader. It only uses a
// separately registered refraction type, and must remain invisible otherwise.
// Never mutate/remove the stock folder material, and never capture the screen.
static CFTimeInterval GFFolderLensRetryAfter = 0;
static char kGFFolderLensOverlayKey;

static void GFFolderNativeLensInstall(UIView *host, BOOL enabled) {
    if (!host || ![NSThread isMainThread]) return;
    GFNativeLiveGlassOverlay *overlay =
        objc_getAssociatedObject(host, &kGFFolderLensOverlayKey);

    if (!enabled || !host.window ||
        CGRectGetWidth(host.bounds) < 32.0 ||
        CGRectGetHeight(host.bounds) < 32.0) {
        if (overlay) {
            [overlay removeFromSuperview];
            objc_setAssociatedObject(host, &kGFFolderLensOverlayKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    if (overlay) {
        if (overlay.superview != host) {
            [overlay removeFromSuperview];
            objc_setAssociatedObject(host, &kGFFolderLensOverlayKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            overlay.frame = host.bounds;
            overlay.gfPreferredRadius = host.layer.cornerRadius;
            [overlay setNeedsLayout];
            return;
        }
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (now < GFFolderLensRetryAfter) return;
    NSString *type = GFNativeAvailableFilterType();
    if (!type || !NSClassFromString(@"CABackdropLayer")) {
        // Avoid probing private CAFilter factories on every icon layout frame.
        GFFolderLensRetryAfter = now + 8.0;
        static dispatch_once_t logOnce;
        dispatch_once(&logOnce, ^{
            NSLog(@"[GFOptics03] Folder refraction unavailable: no registered compatible CAFilter; preserving original material");
        });
        return;
    }

    GFNativeDirectBackdropView *provider =
        [[GFNativeDirectBackdropView alloc] initWithFrame:host.bounds];
    provider.gfRefractiveType = type;
    GFNativeLiveGlassOverlay *lens =
        [[GFNativeLiveGlassOverlay alloc] initWithFrame:host.bounds];
    lens.userInteractionEnabled = NO;
    lens.opaque = NO;
    lens.backgroundColor = UIColor.clearColor;
    lens.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
    lens.gfPreferredRadius = host.layer.cornerRadius;
    lens.hidden = YES; // never show an unverified bridge
    lens.provider = provider;
    provider.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
    [lens addSubview:provider];
    // The existing light/reflection layer remains above this experiment.
    [host insertSubview:lens atIndex:0];
    objc_setAssociatedObject(host, &kGFFolderLensOverlayKey, lens,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [lens setNeedsLayout];
    [lens layoutIfNeeded];

    // 'Attached' means the filter was accepted by CA, NOT proof that the
    // compositor executed a physical refraction shader on the wallpaper.
    if (GFNativeLiveVendorAttached(provider)) {
        lens.verified = YES;
        lens.hidden = NO;
        static dispatch_once_t acceptedOnce;
        dispatch_once(&acceptedOnce, ^{
            NSLog(@"[GFOptics03] Folder refraction filter attached: %@ (visual pixel displacement not yet verified)", type);
        });
    } else {
        __weak UIView *weakHost = host;
        __weak GFNativeLiveGlassOverlay *weakLens = lens;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *strongHost = weakHost;
            GFNativeLiveGlassOverlay *strongLens = weakLens;
            if (!strongHost || !strongLens ||
                objc_getAssociatedObject(strongHost, &kGFFolderLensOverlayKey) != strongLens)
                return;
            if (GFNativeLiveVendorAttached(strongLens.provider)) {
                strongLens.verified = YES;
                strongLens.hidden = NO;
            } else {
                [strongLens removeFromSuperview];
                objc_setAssociatedObject(strongHost, &kGFFolderLensOverlayKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                GFFolderLensRetryAfter = CACurrentMediaTime() + 8.0;
                NSLog(@"[GFOptics03] Folder filter attachment failed; original material unchanged");
            }
        });
    }
}

#endif
