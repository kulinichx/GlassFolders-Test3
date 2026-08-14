#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSliderTableCell.h>
#import <spawn.h>
#import <roothide.h>
#import <math.h>

extern char **environ;


@interface GFPercentSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, weak) UISlider *gfBoundSlider;
@property (nonatomic, strong) UISelectionFeedbackGenerator *gfFeedback;
@property (nonatomic, assign) NSInteger gfLastDetent;
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
    self.gfLastDetent = NSIntegerMin;
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

    NSInteger percent = (NSInteger)lroundf(slider.value / 5.0f) * 5;
    percent = MAX(0, MIN(100, percent));
    self.gfPercentLabel.text =
        [NSString stringWithFormat:@"%ld%%", (long)percent];
}

- (void)gfSliderChanged:(UISlider *)sender {
    /*
     * 5% magnetic detents: 0, 5, 10 ... 100.
     *
     * The slider remains interactive, but the value is quantized immediately
     * to the nearest 5%. This avoids meaningless 43.7 / 47.2 values and gives
     * a system-picker-like stepping feel.
     */
    NSInteger detent = (NSInteger)lroundf(sender.value / 5.0f) * 5;
    detent = MAX(0, MIN(100, detent));

    if ((NSInteger)lroundf(sender.value) != detent) {
        [sender setValue:(float)detent animated:NO];
    }

    /*
     * Persist the snapped value explicitly.
     * PSSliderTableCell also has its own preference-writing target, but target
     * invocation order is not something we should rely on. Writing the detent
     * here guarantees that a Respring reads the exact 5% step.
     */
    double storedValue = (double)detent;
    CFNumberRef number = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberDoubleType,
        &storedValue
    );

    if (number) {
        CFPreferencesSetAppValue(
            CFSTR("GlassStrength"),
            number,
            CFSTR("com.local.glassfolders")
        );
        CFPreferencesAppSynchronize(CFSTR("com.local.glassfolders"));
        CFRelease(number);
    }

    if (self.gfLastDetent != detent) {
        self.gfLastDetent = detent;

        if (!self.gfFeedback) {
            self.gfFeedback = [[UISelectionFeedbackGenerator alloc] init];
        }

        [self.gfFeedback prepare];
        [self.gfFeedback selectionChanged];
    }

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
