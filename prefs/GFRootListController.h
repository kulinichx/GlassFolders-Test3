#import <Preferences/PSListController.h>

@interface GFPreferencesController : PSListController
- (NSString *)gfText:(NSString *)key;
- (void)gfShowMessage:(NSString *)message;
- (void)respring;
@end

@interface GFRootListController : GFPreferencesController
- (NSString *)authorValue:(PSSpecifier *)specifier;
- (NSString *)licenseSummary:(PSSpecifier *)specifier;
@end

@interface GFLicenseListController : GFPreferencesController
@property (nonatomic, assign) BOOL gfCopiedDeviceCode;
@property (nonatomic, assign) BOOL gfCreatedDeviceProof;
@property (nonatomic, assign) BOOL gfReplacingLicense;
- (NSString *)licenseStatus:(PSSpecifier *)specifier;
- (NSString *)licenseIdentifier:(PSSpecifier *)specifier;
- (void)copyDeviceCode;
- (void)bindDevice;
- (void)pasteLicense;
- (void)beginLicenseReplacement;
- (void)cancelLicenseReplacement;
- (void)removeLicense;
@end
