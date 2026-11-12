#import "GFRootListController.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <roothide.h>
#import <math.h>
#import "../GFLicense.h"

extern char **environ;


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

- (NSUserDefaults *)layoutPreferences {
    // UI expansion state stays separate from the tweak's live settings.
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.kulinich.glassfolders.settings-layout"];
}

- (BOOL)sectionExpanded:(NSString *)section {
    return [[self layoutPreferences] boolForKey:section];
}

- (void)configureSectionCell:(UITableViewCell *)cell specifier:(PSSpecifier *)specifier {
    NSString *section = [specifier propertyForKey:@"gfCollapseID"];
    BOOL expanded = [self sectionExpanded:section];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = nil;
    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:expanded ? @"chevron.up" : @"chevron.down"]];
    arrow.tintColor = UIColor.tertiaryLabelColor;
    arrow.isAccessibilityElement = NO;
    cell.accessoryView = arrow;
    cell.accessibilityTraits |= UIAccessibilityTraitButton;
    cell.accessibilityValue = [self gfText:expanded ? @"Expanded" : @"Collapsed"];
    cell.accessibilityHint = [self gfText:@"Tap to expand or collapse."];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"gfCollapseID"]) {
        [self configureSectionCell:cell specifier:specifier];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *section = [specifier propertyForKey:@"gfCollapseID"];
    if (section) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [[self layoutPreferences] setBool:![self sectionExpanded:section] forKey:section];
        [self reloadSpecifiers];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSString *)licenseSummary:(PSSpecifier *)specifier {
    (void)specifier;
    return [self gfText:GFLicenseCurrentInfo() ? @"Activated" : @"Not Activated"];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        BOOL activated = GFLicenseCurrentInfo() != nil;
        NSNumber *style = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Style"),
            CFSTR("com.kulinich.glassfolders")));
        NSInteger selectedStyle = style.integerValue == 1 ? 1 : 0;
        NSMutableArray *items = [NSMutableArray array];
        for (PSSpecifier *specifier in [self loadSpecifiersFromPlistName:@"Root" target:self]) {
            if (activated && [[specifier propertyForKey:@"gfVisibility"] isEqualToString:@"unactivated"]) continue;
            NSString *section = [specifier propertyForKey:@"gfSection"];
            if (section && ![self sectionExpanded:section]) continue;
            NSNumber *requiredStyle = [specifier propertyForKey:@"gfStyle"];
            if (requiredStyle && requiredStyle.integerValue != selectedStyle) continue;
            [items addObject:specifier];
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
                    [self gfShowMessage:[self gfText:@"License saved. Tap Reload SpringBoard to enable glass effects."]];
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
                [self gfShowMessage:[self gfText:@"License removed. Tap Reload SpringBoard."]];
            } else [self gfShowMessage:[self gfText:error.localizedDescription]];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
