#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSliderTableCell.h>
#import <spawn.h>
#import <roothide.h>
#import <math.h>

extern char **environ;


@interface GFPercentSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, weak) UISlider *gfBoundSlider;
@end

@implementation GFPercentSliderCell

- (void)gfEnsurePercentLabel {
    if (self.gfPercentLabel) return;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font =
        [UIFont monospacedDigitSystemFontOfSize:15.0
                                         weight:UIFontWeightMedium];
    label.userInteractionEnabled = NO;

    [self.contentView addSubview:label];
    self.gfPercentLabel = label;
}

- (UISlider *)gfSlider {
    UIControl *control = [self control];

    if ([control isKindOfClass:[UISlider class]]) {
        return (UISlider *)control;
    }

    return nil;
}

- (void)gfBindSliderIfNeeded {
    UISlider *slider = [self gfSlider];
    if (!slider) return;

    if (self.gfBoundSlider != slider) {
        if (self.gfBoundSlider) {
            [self.gfBoundSlider removeTarget:self
                                       action:@selector(gfSliderChanged:)
                             forControlEvents:UIControlEventValueChanged];
        }

        self.gfBoundSlider = slider;

        [slider addTarget:self
                   action:@selector(gfSliderChanged:)
         forControlEvents:UIControlEventValueChanged];
    }
}

- (void)gfUpdatePercentLabel {
    UISlider *slider = [self gfSlider];

    if (!slider) {
        self.gfPercentLabel.text = @"";
        return;
    }

    NSInteger percent = (NSInteger)lroundf(slider.value);
    self.gfPercentLabel.text =
        [NSString stringWithFormat:@"%ld%%", (long)percent];
}

- (void)gfSliderChanged:(UISlider *)sender {
    [self gfUpdatePercentLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self gfEnsurePercentLabel];
    [self gfBindSliderIfNeeded];

    UISlider *slider = [self gfSlider];

    if (!slider) {
        self.gfPercentLabel.hidden = YES;
        return;
    }

    self.gfPercentLabel.hidden = NO;

    CGRect bounds = self.contentView.bounds;

    /*
     * Fix Test5.2 overlap:
     * percentage owns a dedicated LEFT column.
     * The slider starts after it, so the track never runs under the number.
     */
    const CGFloat leftInset = 14.0;
    const CGFloat valueWidth = 52.0;
    const CGFloat gap = 8.0;
    const CGFloat rightInset = 18.0;

    self.gfPercentLabel.frame = CGRectMake(
        leftInset,
        0.0,
        valueWidth,
        CGRectGetHeight(bounds)
    );

    CGRect sliderFrame = slider.frame;
    sliderFrame.origin.x = leftInset + valueWidth + gap;
    sliderFrame.size.width =
        MAX(120.0,
            CGRectGetWidth(bounds) -
            sliderFrame.origin.x -
            rightInset);

    slider.frame = sliderFrame;

    [self gfUpdatePercentLabel];
}

@end


@implementation GFRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers =
            [self loadSpecifiersFromPlistName:@"Root" target:self];
    }

    return _specifiers;
}

- (void)respring {
    NSString *sbreloadPath = jbroot(@"/usr/bin/sbreload");

    if (sbreloadPath.length > 0) {
        const char *path = sbreloadPath.fileSystemRepresentation;

        char *const argv[] = {
            (char *)path,
            NULL
        };

        pid_t pid = 0;
        int result =
            posix_spawn(&pid, path, NULL, NULL, argv, environ);

        if (result == 0) {
            return;
        }
    }

    NSString *killallPath = jbroot(@"/usr/bin/killall");

    if (killallPath.length > 0) {
        const char *path = killallPath.fileSystemRepresentation;

        char *const argv[] = {
            (char *)path,
            (char *)"-9",
            (char *)"SpringBoard",
            NULL
        };

        pid_t pid = 0;
        posix_spawn(&pid, path, NULL, NULL, argv, environ);
    }
}

@end
