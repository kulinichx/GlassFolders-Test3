#import <Preferences/PSListController.h>

@interface GFRootListController : PSListController
- (void)respring;
- (NSString *)authorValue:(PSSpecifier *)specifier;
- (NSString *)licenseStatus:(PSSpecifier *)specifier;
- (void)copyDeviceCode;
- (void)bindDevice;
- (void)pasteLicense;
- (void)removeLicense;
@end
