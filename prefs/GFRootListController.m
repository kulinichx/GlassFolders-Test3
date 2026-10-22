#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSliderTableCell.h>
#import <spawn.h>
#import <roothide.h>
#import <math.h>
#import "../GFLicense.h"

extern char **environ;


@interface GFPercentSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *gfPercentLabel;
@property (nonatomic, weak) UISlider *gfBoundSlider;
@property (nonatomic, strong) UIImpactFeedbackGenerator *gfImpactFeedback;
@property (nonatomic, assign) NSInteger gfLastDetent;
@property (nonatomic, assign) NSInteger gfPendingDetent;
@end

@implementation GFPercentSliderCell

- (void)gfEnsurePercentLabel {
    if (self.gfPercentLabel) {
        return;
    }

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font =
        [UIFont monospacedDigitSystemFontOfSize:15.0
                                         weight:UIFontWeightSemibold];

    /*
     * This opaque dynamic background also masks any internal slider track
     * that PSSliderTableCell may attempt to draw under the number.
     */
    label.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    label.layer.cornerRadius = 7.0;
    label.clipsToBounds = YES;
    label.userInteractionEnabled = NO;

    [self.contentView addSubview:label];

    self.gfPercentLabel = label;
    self.gfLastDetent = NSIntegerMin;
    self.gfPendingDetent = NSIntegerMin;
}

- (UISlider *)gfSlider {
    UIControl *control = [self control];

    if ([control isKindOfClass:[UISlider class]]) {
        return (UISlider *)control;
    }

    return nil;
}

- (NSInteger)gfDetentForValue:(float)value {
    NSInteger detent = (NSInteger)lroundf(value / 5.0f) * 5;
    return MAX(0, MIN(100, detent));
}

- (void)gfPersistDetent:(NSInteger)detent {
    detent = MAX(0, MIN(100, detent));

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
}

- (void)gfEnsureImpactGenerator {
    if (!self.gfImpactFeedback) {
        /*
         * Rigid is intentionally more mechanical/crisp than selection haptics.
         * It is still instantiated only inside Settings and only used while
         * the user is actively moving across 5% detents.
         */
        self.gfImpactFeedback =
            [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleRigid];
    }
}

- (void)gfBindSliderIfNeeded {
    UISlider *slider = [self gfSlider];

    if (!slider) {
        return;
    }

    if (self.gfBoundSlider != slider) {
        if (self.gfBoundSlider) {
            [self.gfBoundSlider
                removeTarget:self
                      action:NULL
            forControlEvents:UIControlEventAllEvents];
        }

        self.gfBoundSlider = slider;
        slider.continuous = YES;

        [slider addTarget:self
                   action:@selector(gfSliderTouchDown:)
         forControlEvents:UIControlEventTouchDown];

        [slider addTarget:self
                   action:@selector(gfSliderChanged:)
         forControlEvents:UIControlEventValueChanged];

        [slider addTarget:self
                   action:@selector(gfSliderTouchEnded:)
         forControlEvents:(UIControlEventTouchUpInside |
                           UIControlEventTouchUpOutside |
                           UIControlEventTouchCancel)];

        NSInteger initial = [self gfDetentForValue:slider.value];
        self.gfLastDetent = initial;
        self.gfPendingDetent = initial;
    }
}

- (void)gfUpdatePercentLabel {
    UISlider *slider = [self gfSlider];

    if (!slider) {
        self.gfPercentLabel.text = @"";
        return;
    }

    NSInteger detent = [self gfDetentForValue:slider.value];

    self.gfPercentLabel.text =
        [NSString stringWithFormat:@"%ld%%", (long)detent];
}

- (void)gfSliderTouchDown:(UISlider *)sender {
    NSInteger detent = [self gfDetentForValue:sender.value];

    self.gfLastDetent = detent;
    self.gfPendingDetent = detent;

    [self gfEnsureImpactGenerator];
    [self.gfImpactFeedback prepare];
}

- (void)gfSliderChanged:(UISlider *)sender {
    /*
     * Alarm-wheel style:
     * - thumb remains smooth under the finger
     * - every 5% threshold emits one crisp "tick"
     * - displayed value follows the nearest 5% detent
     * - thumb magnetically settles to the exact detent on release
     */
    NSInteger detent = [self gfDetentForValue:sender.value];
    self.gfPendingDetent = detent;

    if (self.gfLastDetent != detent) {
        self.gfLastDetent = detent;

        [self gfEnsureImpactGenerator];

        /*
         * Stronger than the previous selection haptic.
         * 0.68 is intentionally noticeable without feeling like a heavy tap.
         */
        [self.gfImpactFeedback impactOccurredWithIntensity:0.68];
        [self.gfImpactFeedback prepare];
    }

    self.gfPercentLabel.text =
        [NSString stringWithFormat:@"%ld%%", (long)detent];
}

- (void)gfSliderTouchEnded:(UISlider *)sender {
    NSInteger detent = self.gfPendingDetent;

    if (detent == NSIntegerMin) {
        detent = [self gfDetentForValue:sender.value];
    }

    detent = MAX(0, MIN(100, detent));

    /*
     * Magnetic settle only at finger release.
     * This preserves smooth dragging while still ending on exact 5% values.
     */
    [sender setValue:(float)detent animated:YES];
    [self gfPersistDetent:detent];

    self.gfPercentLabel.text =
        [NSString stringWithFormat:@"%ld%%", (long)detent];

    self.gfPendingDetent = detent;
    self.gfLastDetent = detent;
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
     * Reserve a real percentage column with a visible empty gap after it.
     * The slider track begins only after this area.
     */
    const CGFloat leftInset = 14.0;
    const CGFloat valueWidth = 64.0;
    const CGFloat gap = 18.0;
    const CGFloat rightInset = 18.0;

    self.gfPercentLabel.frame = CGRectMake(
        leftInset,
        5.0,
        valueWidth,
        MAX(28.0, CGRectGetHeight(bounds) - 10.0)
    );

    CGRect sliderFrame = slider.frame;
    sliderFrame.origin.x = leftInset + valueWidth + gap;
    sliderFrame.size.width =
        MAX(120.0,
            CGRectGetWidth(bounds) -
            sliderFrame.origin.x -
            rightInset);

    slider.frame = sliderFrame;

    /*
     * Keep the opaque percentage badge above the slider's internal subviews.
     * Even if Preferences relayouts its track, it cannot visually cross the
     * number.
     */
    [self.contentView bringSubviewToFront:self.gfPercentLabel];

    [self gfUpdatePercentLabel];
}

@end


@implementation GFPreferencesController

- (NSString *)gfText:(NSString *)key {
    return [[NSBundle bundleForClass:self.class] localizedStringForKey:key value:key table:@"Root"];
}

- (void)gfShowMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self gfText:@"License Management"]
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self gfText:@"OK"] style:UIAlertActionStyleDefault handler:nil]];
    // Action handlers may run while the input alert is still dismissing.
    // Wait for that transition before presenting the result.
    UIViewController *presented = self.presentedViewController;
    id<UIViewControllerTransitionCoordinator> transition = presented.transitionCoordinator;
    if (transition && [transition animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self presentViewController:alert animated:YES completion:nil];
    }]) return;
    if (presented) {
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:alert animated:YES completion:nil];
        }];
    } else [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *identifier = [specifier propertyForKey:@"id"];
    if ([identifier isEqualToString:@"GFLicenseStatus"] ||
        [identifier isEqualToString:@"GFLicenseManagement"]) {
        cell.detailTextLabel.textColor = GFLicenseCurrentInfo() ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    } else if ([identifier isEqualToString:@"GFRemoveLicense"]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
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

@implementation GFRootListController

- (NSString *)licenseSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return [self gfText:GFLicenseCurrentInfo() ? @"Activated" : @"Not Activated"];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        if (GFLicenseCurrentInfo()) {
            NSIndexSet *prompt = [items indexesOfObjectsPassingTest:^BOOL(PSSpecifier *specifier, NSUInteger index, BOOL *stop) {
                (void)index; (void)stop;
                return [[specifier propertyForKey:@"gfVisibility"] isEqualToString:@"unactivated"];
            }];
            [items removeObjectsAtIndexes:prompt];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (NSString *)authorValue:(PSSpecifier *)specifier {
    (void)specifier;
    return @"kulinich";
}

@end

@implementation GFLicenseListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self gfText:@"License Management"];
}

- (NSString *)licenseStatus:(PSSpecifier *)specifier {
    (void)specifier;
    return [self gfText:GFLicenseCurrentInfo() ? @"Activated" : @"Not Activated"];
}

- (NSString *)licenseIdentifier:(PSSpecifier *)specifier {
    (void)specifier;
    return GFLicenseCurrentInfo()[@"sid"] ?: @"";
}

- (void)beginLicenseReplacement {
    self.gfReplacingLicense = YES;
    self.gfCopiedDeviceCode = NO;
    self.gfCreatedDeviceProof = NO;
    [self reloadSpecifiers];
}

- (void)cancelLicenseReplacement {
    self.gfReplacingLicense = NO;
    self.gfCopiedDeviceCode = NO;
    self.gfCreatedDeviceProof = NO;
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        BOOL activated = GFLicenseCurrentInfo() != nil;
        BOOL flow = !activated || self.gfReplacingLicense;
        NSMutableArray *items = [NSMutableArray array];
        for (PSSpecifier *specifier in [self loadSpecifiersFromPlistName:@"License" target:self]) {
            // Both pages share Root.strings rather than a separate License table.
            if (specifier.name.length) [specifier setName:[self gfText:specifier.name]];
            NSString *footer = [specifier propertyForKey:@"footerText"];
            if (footer.length) [specifier setProperty:[self gfText:footer] forKey:@"footerText"];
            NSString *visibility = [specifier propertyForKey:@"gfVisibility"];
            if ([visibility isEqualToString:@"activated"] && !activated) continue;
            if ([visibility isEqualToString:@"flow"] && !flow) continue;
            if ([visibility isEqualToString:@"replacement"] && (!activated || self.gfReplacingLicense)) continue;
            if ([visibility isEqualToString:@"cancelReplacement"] && (!activated || !self.gfReplacingLicense)) continue;
            NSString *identifier = [specifier propertyForKey:@"id"];
            if ([identifier isEqualToString:@"GFLicenseInfo"]) {
                [specifier setProperty:[self gfText:activated ? @"Permanent license for this device." : @"Activate to enable glass effects."] forKey:@"footerText"];
            } else if ([identifier isEqualToString:@"GFCopyDeviceCode"] && self.gfCopiedDeviceCode) {
                [specifier setName:[self gfText:@"1. Device Code Copied ✓"]];
            } else if ([identifier isEqualToString:@"GFBindDevice"] && self.gfCreatedDeviceProof) {
                [specifier setName:[self gfText:@"2. Device Proof Copied ✓"]];
            }
            [items addObject:specifier];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (void)copyDeviceCode {
    NSString *code = GFLicenseDeviceCode();
    if (!code.length) { [self gfShowMessage:[self gfText:@"Device identifier unavailable"]]; return; }
    UIPasteboard.generalPasteboard.string = code;
    self.gfCopiedDeviceCode = YES;
    [self reloadSpecifiers];
    [self gfShowMessage:[self gfText:@"Device Code copied. Send it to the developer to receive a binding challenge."]];
}

- (void)gfPresentInputForBinding:(BOOL)binding {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        [self gfText:binding ? @"Bind This Device" : @"Paste License"]
        message:[self gfText:binding ? @"Paste the binding challenge from the developer. It expires after five minutes."
                                    : @"Paste the GlassFolders license from the developer."]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.placeholder = binding ? @"GFC1…" : @"GF1.…";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:[self gfText:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[self gfText:binding ? @"Create Device Proof" : @"Activate"]
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *input = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSError *error = nil;
            if (binding) {
                NSString *proof = GFLicenseCreateProof(input, &error);
                if (proof) {
                    UIPasteboard.generalPasteboard.string = proof;
                    self.gfCreatedDeviceProof = YES;
                    [self reloadSpecifiers];
                    [self gfShowMessage:[self gfText:@"Device proof copied. Send it to the developer for verification and signing."]];
                } else [self gfShowMessage:[self gfText:error.localizedDescription]];
            } else {
                if (GFLicenseStore(input, &error)) {
                    self.gfReplacingLicense = NO;
                    self.gfCopiedDeviceCode = NO;
                    self.gfCreatedDeviceProof = NO;
                    [self reloadSpecifiers];
                    [self gfShowMessage:[self gfText:@"License saved. Tap Apply & Respring to enable glass effects."]];
                } else [self gfShowMessage:[self gfText:error.localizedDescription]];
            }
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)bindDevice { [self gfPresentInputForBinding:YES]; }
- (void)pasteLicense { [self gfPresentInputForBinding:NO]; }

- (void)removeLicense {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self gfText:@"Remove License"]
        message:[self gfText:@"Remove this device's saved license? Glass effects will stop after respring."]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self gfText:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[self gfText:@"Remove License"] style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
            NSError *error = nil;
            if (GFLicenseStore(nil, &error)) {
                self.gfReplacingLicense = NO;
                self.gfCopiedDeviceCode = NO;
                self.gfCreatedDeviceProof = NO;
                [self reloadSpecifiers];
                [self gfShowMessage:[self gfText:@"License removed. Tap Apply & Respring."]];
            } else [self gfShowMessage:[self gfText:error.localizedDescription]];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
