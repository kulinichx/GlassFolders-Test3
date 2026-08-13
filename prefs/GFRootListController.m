#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSliderTableCell.h>
#import <spawn.h>
#import <roothide.h>
#import <math.h>

extern char **environ;


/*
 * Lightweight percent slider.
 *
 * IMPORTANT:
 * PSSliderTableCell is imported from Theos' Preferences headers.
 * Do NOT redeclare it locally — its real superclass is PSControlTableCell.
 */
@interface GFPercentSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, weak) UISlider *gfBoundSlider;
@end

@implementation GFPercentSliderCell

- (void)gfEnsurePercentLabel {
    if (self.gfPercentLabel) {
        return;
    }

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentRight;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:15.0
                                                  weight:UIFontWeightRegular];
    label.userInteractionEnabled = NO;

    [self.contentView addSubview:label];
    self.gfPercentLabel = label;
}

- (UISlider *)gfSlider {
    /*
     * PSControlTableCell exposes -control.
     * We still verify the runtime class before treating it as UISlider.
     */
    UIControl *control = [self control];

    if ([control isKindOfClass:[UISlider class]]) {
        return (UISlider *)control;
    }

    return nil;
}

- (void)gfBindSliderIfNeeded {
    UISlider *slider = [self gfSlider];

    if (!slider) {
        return;
    }

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
     * Give the percentage a fixed, generous area so "100%" never clips.
     * Shrink only the slider — don't let the number overlap the cell edge.
     */
    const CGFloat rightInset = 16.0;
    const CGFloat valueWidth = 58.0;
    const CGFloat gap = 10.0;

    CGRect sliderFrame = slider.frame;
    CGFloat maximumSliderRight =
        CGRectGetWidth(bounds) - rightInset - valueWidth - gap;

    if (CGRectGetMaxX(sliderFrame) > maximumSliderRight) {
        sliderFrame.size.width =
            MAX(90.0, maximumSliderRight - sliderFrame.origin.x);
        slider.frame = sliderFrame;
    }

    self.gfPercentLabel.frame = CGRectMake(
        CGRectGetMaxX(slider.frame) + gap,
        0.0,
        valueWidth,
        CGRectGetHeight(bounds)
    );

    [self gfUpdatePercentLabel];
}

@end


@implementation GFRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }

    return _specifiers;
}

- (void)respring {
    /*
     * Resolve the randomized RootHide jbroot instead of hard-coding it.
     */
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

    /*
     * Fallback only if sbreload could not be spawned.
     */
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
