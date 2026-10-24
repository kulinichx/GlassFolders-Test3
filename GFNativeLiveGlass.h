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
@end
@implementation GFNativeLiveGlassOverlay
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.provider) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.provider.frame = self.bounds;
    CGFloat radius = MIN(24.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.14);
    self.layer.cornerRadius = radius;
    self.provider.layer.cornerRadius = radius;
    self.provider.layer.masksToBounds = YES;
    // Use only the refractive rim. This prevents a single provider view
    // from replacing the whole card with an opaque rectangle on failure.
    CGRect outerRect = self.bounds;
    CGRect innerRect = CGRectInset(outerRect, 15.0, 15.0);
    CGFloat innerRadius = MAX(0.0, radius - 15.0);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:outerRect
                                                     cornerRadius:radius];
    [shape appendPath:[UIBezierPath bezierPathWithRoundedRect:innerRect
                                                cornerRadius:innerRadius]];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = outerRect;
    mask.path = shape.CGPath;
    mask.fillRule = kCAFillRuleEvenOdd;
    self.layer.mask = mask;
    [CATransaction commit];
}
@end

// Preferred: use a separately installed, already-loaded live compositor
// provider if one is available. We do not bundle or copy its implementation.
static UIView *GFNativeLiveVendorView(CGRect frame) {
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

#endif
