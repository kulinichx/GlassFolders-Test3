#ifndef GF_NOTIFICATION_GLASS_VIEW_H
#define GF_NOTIFICATION_GLASS_VIEW_H

// A stack transition changes decoration, never the live backdrop recipe.
@interface GFNotificationGlassView : GFLockScreenGlassView
@property (nonatomic, assign) BOOL gfStacked;
- (void)gfRefreshStackAppearance;
@end
@implementation GFNotificationGlassView
- (BOOL)gfUsesNotificationBlurControl {
    return YES;
}
- (void)setGfStacked:(BOOL)stacked {
    if (_gfStacked == stacked) return;
    _gfStacked = stacked;
    [self gfRefreshStackAppearance];
}
- (void)gfRefreshStackAppearance {
    self.gfLockRim.gfSubdued = self.gfStacked;
    [self gfRefreshBodyVeil];
    [self.gfLockRim setNeedsLayout];
}
- (void)gfRefreshMaterial {
    [super gfRefreshMaterial];
    [self gfRefreshStackAppearance];
}
@end

#endif
