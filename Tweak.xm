#import <UIKit/UIKit.h>

@interface SBFolderIconImageView : UIView
- (UIView *)backgroundView;
- (void)setBackgroundView:(UIView *)backgroundView;
@end

%hook SBFolderIconImageView

- (void)setBackgroundView:(UIView *)backgroundView {
    %orig(backgroundView);
    if (backgroundView) {
        backgroundView.alpha = 0.0;
    }
}

%end
