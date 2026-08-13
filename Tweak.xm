#import <UIKit/UIKit.h>

/*
 * GlassFolders Test3.1
 *
 * Stability fix for Home Screen page scrolling/reuse:
 * Instead of making Apple's original folder background view transparent,
 * replace it at assignment time with a fresh empty UIView.
 *
 * This remains intentionally minimal:
 * - one class
 * - one selector
 * - SpringBoard only
 * - no preferences
 * - no opened-folder hooks
 * - no launchd / filesystem modifications
 */

@interface SBFolderIconImageView : UIView
- (void)setBackgroundView:(UIView *)backgroundView;
@end

%hook SBFolderIconImageView

- (void)setBackgroundView:(UIView *)backgroundView {
    /*
     * SBFolderIconImageView is reused/reconfigured while Home Screen pages
     * scroll. If we only set Apple's original view alpha to 0, SpringBoard
     * can later restore/reconfigure that original material view.
     *
     * Supplying an empty UIView means later alpha/style updates have no
     * blur/material content to bring back, while SpringBoard still receives
     * a valid background view and keeps its normal ownership/animation graph.
     */
    UIView *clearFolderPlate = [[UIView alloc] initWithFrame:CGRectZero];
    clearFolderPlate.backgroundColor = UIColor.clearColor;
    clearFolderPlate.userInteractionEnabled = NO;

    %orig(clearFolderPlate);
}

%end
