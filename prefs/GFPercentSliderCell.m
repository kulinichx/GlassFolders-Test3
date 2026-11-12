#import "GFPercentSliderCell.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

@interface GFPercentSliderCell ()
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, strong) UISlider *gfOwnedSlider;
@property (nonatomic, strong) UIImpactFeedbackGenerator *gfImpactFeedback;
@property (nonatomic, assign) NSInteger gfLastDetent;
@end

@implementation GFPercentSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)identifier
                   specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        [self gfEnsureControls];
        [self gfLoadValue:specifier];
    }
    return self;
}

- (void)gfEnsureControls {
    if (self.gfOwnedSlider) return;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.textLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;
    self.titleLabel.hidden = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    label.backgroundColor = UIColor.clearColor;
    label.userInteractionEnabled = NO;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.continuous = YES;
    slider.clipsToBounds = NO;
    slider.accessibilityLabel = self.specifier.name;
    [slider addTarget:self action:@selector(gfSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(gfSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(gfSliderTouchEnded:)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    [self.contentView addSubview:label];
    [self.contentView addSubview:slider];
    self.gfPercentLabel = label;
    self.gfOwnedSlider = slider;
    self.gfLastDetent = NSIntegerMin;
    // Own both controls: no PSSliderTableCell control/constraint can reclaim the row.
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [label.widthAnchor constraintEqualToConstant:52],
        [label.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [slider.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [slider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
        [slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [slider.heightAnchor constraintEqualToConstant:40]
    ]];
}

- (NSInteger)gfDetentForValue:(float)value {
    return MAX(0, MIN(100, (NSInteger)lroundf(value / 5.0f) * 5));
}

- (void)gfUpdatePercentLabel {
    NSInteger percent = [self gfDetentForValue:self.gfOwnedSlider.value];
    self.gfPercentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
    self.gfOwnedSlider.accessibilityValue = self.gfPercentLabel.text;
}

- (void)gfLoadValue:(PSSpecifier *)specifier {
    if (self.gfOwnedSlider.tracking) return;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *domain = [specifier propertyForKey:@"defaults"];
    double value = [[specifier propertyForKey:@"default"] doubleValue];
    if ([key isKindOfClass:NSString.class] && [domain isKindOfClass:NSString.class]) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
        id stored = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                              (__bridge CFStringRef)domain));
        if (!stored && ([key isEqualToString:@"ClearStrength"] ||
                        [key isEqualToString:@"LiquidGlassStrength"])) {
            stored = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("GlassStrength"),
                                                                (__bridge CFStringRef)domain));
        }
        if (stored && CFGetTypeID((__bridge CFTypeRef)stored) == CFNumberGetTypeID())
            value = [stored doubleValue];
    }
    if (!isfinite(value)) value = 55;
    self.gfOwnedSlider.value = MAX(0, MIN(100, value));
    id enabled = [specifier propertyForKey:@"enabled"];
    self.gfOwnedSlider.enabled = !enabled || [enabled boolValue];
    NSString *name = [key isEqualToString:@"ClearStrength"] ? @"Clear Strength" : @"Liquid Glass Strength";
    self.gfOwnedSlider.accessibilityLabel = [[NSBundle bundleForClass:self.class]
        localizedStringForKey:name value:name table:@"Root"];
    self.gfLastDetent = [self gfDetentForValue:self.gfOwnedSlider.value];
    [self gfUpdatePercentLabel];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self gfEnsureControls];
    [self gfLoadValue:specifier];
    self.textLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;
    self.titleLabel.hidden = YES;
}

- (void)gfPersistValue:(double)value {
    PSSpecifier *specifier = self.specifier;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *domain = [specifier propertyForKey:@"defaults"];
    if (![key isKindOfClass:NSString.class] || !key.length ||
        ![domain isEqualToString:@"com.kulinich.glassfolders"] || !isfinite(value)) return;
    NSNumber *number = @(MAX(0, MIN(100, value)));
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFNumberRef)number,
                             (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.kulinich.glassfolders/preferenceschanged"), NULL, NULL, true);
}

- (void)gfSliderTouchDown:(UISlider *)slider {
    self.gfLastDetent = [self gfDetentForValue:slider.value];
    if (!self.gfImpactFeedback) {
        self.gfImpactFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    }
    [self.gfImpactFeedback prepare];
}

- (void)gfSliderChanged:(UISlider *)slider {
    NSInteger detent = [self gfDetentForValue:slider.value];
    if (detent != self.gfLastDetent) {
        self.gfLastDetent = detent;
        [self.gfImpactFeedback impactOccurredWithIntensity:0.68];
        [self.gfImpactFeedback prepare];
    }
    [self gfUpdatePercentLabel];
    [self gfPersistValue:slider.value];
}

- (void)gfSliderTouchEnded:(UISlider *)slider {
    NSInteger detent = [self gfDetentForValue:slider.value];
    [slider setValue:(float)detent animated:YES];
    [self gfPersistValue:detent];
    self.gfLastDetent = detent;
    [self gfUpdatePercentLabel];
}

@end
