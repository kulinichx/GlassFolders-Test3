#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <roothide.h>

/*
 * Minimal declaration is intentional. The real class comes from
 * Preferences.framework at runtime.
 */
@interface PSSliderTableCell : UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier
                    specifier:(PSSpecifier *)specifier;
- (UIControl *)control;
@end


@interface GFPercentSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, weak) UISlider *gfSlider;
@end

@implementation GFPercentSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];

    if (self) {
        _gfPercentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _gfPercentLabel.textAlignment = NSTextAlignmentRight;
        _gfPercentLabel.textColor = UIColor.secondaryLabelColor;
        _gfPercentLabel.font =
            [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightRegular];

        [self.contentView addSubview:_gfPercentLabel];
    }

    return self;
}

- (void)gfBindSliderIfNeeded {
    UIControl *control = [self control];

    if (![control isKindOfClass:[UISlider class]]) {
        return;
    }

    UISlider *slider = (UISlider *)control;

    if (self.gfSlider != slider) {
        if (self.gfSlider) {
            [self.gfSlider removeTarget:self
                                  action:@selector(gfSliderChanged:)
                        forControlEvents:UIControlEventValueChanged];
        }

        self.gfSlider = slider;

        [slider addTarget:self
                   action:@selector(gfSliderChanged:)
         forControlEvents:UIControlEventValueChanged];
    }

    [self gfUpdatePercentLabel];
}

- (void)gfSliderChanged:(UISlider *)slider {
    [self gfUpdatePercentLabel];
}

- (void)gfUpdatePercentLabel {
    if (!self.gfSlider) {
        self.gfPercentLabel.text = @"";
        return;
    }

    NSInteger percent = (NSInteger)lroundf(self.gfSlider.value);
    self.gfPercentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self gfBindSliderIfNeeded];

    UISlider *slider = self.gfSlider;
    if (!slider) return;

    CGRect contentBounds = self.contentView.bounds;

    CGFloat valueWidth = 54.0;
    CGFloat gap = 10.0;
    CGFloat rightInset = 16.0;

    CGRect sliderFrame = slider.frame;
    CGFloat maxRight =
        CGRectGetWidth(contentBounds) - rightInset - valueWidth - gap;

    if (CGRectGetMaxX(sliderFrame) > maxRight) {
        sliderFrame.size.width = MAX(80.0, maxRight - sliderFrame.origin.x);
        slider.frame = sliderFrame;
    }

    self.gfPercentLabel.frame = CGRectMake(
        CGRectGetMaxX(slider.frame) + gap,
        0.0,
        valueWidth,
        CGRectGetHeight(contentBounds)
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
     * RootHide randomizes jbroot. Never hard-code /var/jb or a .jbroot-* path.
     */
    NSString *toolPath = jbroot(@"/usr/bin/sbreload");

    if (toolPath.length == 0) {
        return;
    }

    const char *path = toolPath.fileSystemRepresentation;
    char *const argv[] = {
        (char *)path,
        NULL
    };

    pid_t pid = 0;
    int status = posix_spawn(&pid, path, NULL, NULL, argv, NULL);

    if (status != 0) {
        /*
         * Lightweight fallback. killall is also resolved through jbroot.
         * This branch runs only if sbreload failed to spawn.
         */
        NSString *killallPath = jbroot(@"/usr/bin/killall");
        const char *killPath = killallPath.fileSystemRepresentation;

        if (killPath) {
            char *const fallbackArgv[] = {
                (char *)killPath,
                (char *)"-9",
                (char *)"SpringBoard",
                NULL
            };

            posix_spawn(&pid, killPath, NULL, NULL, fallbackArgv, NULL);
        }
    }
}

@end
