#ifndef GF_LOCK_MATERIAL_VISIBILITY_H
#define GF_LOCK_MATERIAL_VISIBILITY_H

static char kGFLockMaterialVisibilityKey;

@interface GFLockMaterialVisibility : NSObject
@property (nonatomic, weak) UIView *background;
@property (nonatomic, weak) UIView *glass;
@property (nonatomic, assign) BOOL nativeHidden;
@property (nonatomic, assign) BOOL suppressingNative;
@property (nonatomic, assign) BOOL suspended;
- (void)attachBackground:(UIView *)background glass:(UIView *)glass;
- (void)suppressNativeBackground;
- (void)restore;
@end

@implementation GFLockMaterialVisibility
- (void)attachBackground:(UIView *)background glass:(UIView *)glass {
    self.background = background;
    self.glass = glass;
    self.nativeHidden = background.hidden;
    glass.alpha = background.alpha;
    glass.hidden = self.nativeHidden;
    objc_setAssociatedObject(background, &kGFLockMaterialVisibilityKey, self,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)suppressNativeBackground {
    self.suppressingNative = YES;
    self.background.hidden = YES;
    self.suppressingNative = NO;
}
- (void)setSuspended:(BOOL)suspended {
    _suspended = suspended;
    self.glass.hidden = suspended || self.nativeHidden;
}
- (void)restore {
    UIView *background = self.background;
    if (background && objc_getAssociatedObject(background, &kGFLockMaterialVisibilityKey) == self) {
        // Detach first so restoration is not intercepted as another system update.
        objc_setAssociatedObject(background, &kGFLockMaterialVisibilityKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        background.hidden = self.nativeHidden;
    }
    self.background = nil;
    self.glass = nil;
}
@end

static void GFLockMaterialAlphaChanged(UIView *background, CGFloat alpha) {
    GFLockMaterialVisibility *visibility =
        objc_getAssociatedObject(background, &kGFLockMaterialVisibilityKey);
    // Called inside the original UIKit animation transaction, without a layout pass.
    if (visibility && visibility.glass.alpha != alpha) visibility.glass.alpha = alpha;
}

static BOOL GFLockMaterialHiddenValue(UIView *background, BOOL hidden) {
    GFLockMaterialVisibility *visibility =
        objc_getAssociatedObject(background, &kGFLockMaterialVisibilityKey);
    if (!visibility) return hidden;
    if (!visibility.suppressingNative) {
        visibility.nativeHidden = hidden;
        visibility.glass.hidden = hidden || visibility.suspended;
    }
    return YES;
}

#endif
