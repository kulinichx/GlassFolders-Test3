#pragma once

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import "GFLicensePublicKey.h"

// Shared by SpringBoard and the preference bundle. No issuer private key or
// writable "activated" flag is trusted by either process.
static NSString * const GFLicensePreferenceKey = @"OfflineLicense";
static CFStringRef const GFLicenseDomain = CFSTR("com.kulinich.glassfolders");

static inline NSString *GFLicenseSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); ++i) [hex appendFormat:@"%02X", digest[i]];
    return hex;
}

static inline BOOL GFLicenseMatches(NSString *text, NSString *pattern) {
    return [text isKindOfClass:NSString.class] &&
        [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static inline NSString *GFLicenseEncode(NSData *data) {
    if (!data) return nil;
    NSString *s = [data base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static inline NSData *GFLicenseDecode(NSString *text) {
    if (!GFLicenseMatches(text, @"^[A-Za-z0-9_-]+$") || text.length % 4 == 1) return nil;
    NSString *s = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                   stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (s.length % 4) s = [s stringByAppendingString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:s options:0];
    return [GFLicenseEncode(data) isEqualToString:text] ? data : nil;
}

// UniqueChipID is consumed only in memory, never logged or stored. Hardware
// identity does not depend on Settings/SpringBoard IDFV, bundle IDs or jbroot.
static inline NSString *GFLicenseDeviceCode(void) {
    static NSString *code;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (!handle) return;
        typedef CFPropertyListRef (*GFCopyAnswer)(CFStringRef);
        GFCopyAnswer copyAnswer = (GFCopyAnswer)dlsym(handle, "MGCopyAnswer");
        CFPropertyListRef raw = copyAnswer ? copyAnswer(CFSTR("UniqueChipID")) : NULL;
        if (raw && CFGetTypeID(raw) == CFNumberGetTypeID()) {
            unsigned long long ecid = [(__bridge NSNumber *)raw unsignedLongLongValue];
            if (ecid) {
                NSString *seed = [NSString stringWithFormat:@"GlassFolders-HW-v1|%016llX", ecid];
                code = [@"GF-" stringByAppendingString:GFLicenseSHA256([seed dataUsingEncoding:NSUTF8StringEncoding])];
            }
        }
        if (raw) CFRelease(raw);
        dlclose(handle);
    });
    return code;
}

static inline NSError *GFLicenseError(NSString *message) {
    return [NSError errorWithDomain:@"GlassFolders.License" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static inline CF_RETURNS_RETAINED SecKeyRef GFLicensePublicKey(NSData *point) {
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 4) return NULL;
    return SecKeyCreateWithData((__bridge CFDataRef)point, (__bridge CFDictionaryRef)@{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256
    }, NULL);
}

static inline NSDictionary *GFLicenseVerify(NSString *wire, NSError **error) {
    NSString *reason = @"Invalid license format";
    do {
        if (![wire isKindOfClass:NSString.class] || wire.length > 4096) break;
        NSArray *parts = [[wire stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                          componentsSeparatedByString:@"."];
        if (parts.count != 3 || ![parts[0] isEqual:@"GF1"]) break;
        NSData *payload = GFLicenseDecode(parts[1]);
        NSData *signature = GFLicenseDecode(parts[2]);
        if (!payload.length || signature.length < 8 || signature.length > 72) break;
        NSData *point = [[NSData alloc] initWithBase64EncodedString:GF_LICENSE_PUBLIC_KEY options:0];
        SecKeyRef key = GFLicensePublicKey(point);
        BOOL valid = key && SecKeyVerifySignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                    (__bridge CFDataRef)payload, (__bridge CFDataRef)signature, NULL);
        if (key) CFRelease(key);
        reason = @"Invalid license signature";
        if (!valid) break;
        id info = [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
        reason = @"Unsupported license payload";
        if (![info isKindOfClass:NSDictionary.class]) break;
        NSSet *expected = [NSSet setWithArray:@[@"v", @"product", @"sid", @"device", @"ent"]];
        if (![[NSSet setWithArray:[info allKeys]] isEqual:expected] ||
            ![info[@"v"] isKindOfClass:NSNumber.class] || ![info[@"v"] isEqual:@1] ||
            ![info[@"product"] isEqual:@"GlassFolders"] ||
            !GFLicenseMatches(info[@"sid"], @"^[A-Za-z0-9_-]{1,64}$") ||
            !GFLicenseMatches(info[@"device"], @"^GF-[A-F0-9]{64}$") ||
            ![info[@"ent"] isEqual:@[@"glassfolders"]]) break;
        reason = @"Device identifier unavailable";
        NSString *device = GFLicenseDeviceCode();
        if (!device.length) break;
        reason = @"License is for another device";
        if (![info[@"device"] isEqual:device]) break;
        return info;
    } while (NO);
    if (error) *error = GFLicenseError(reason);
    return nil;
}

static inline NSString *GFLicenseStoredCode(void) {
    CFPreferencesAppSynchronize(GFLicenseDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)GFLicensePreferenceKey, GFLicenseDomain));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static inline NSDictionary *GFLicenseCurrentInfo(void) {
    return GFLicenseVerify(GFLicenseStoredCode(), NULL);
}

static inline BOOL GFLicenseStore(NSString *wire, NSError **error) {
    if (wire && !GFLicenseVerify(wire, error)) return NO;
    NSString *trimmed = [wire stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    CFPreferencesSetAppValue((__bridge CFStringRef)GFLicensePreferenceKey, (__bridge CFStringRef)trimmed, GFLicenseDomain);
    if (!CFPreferencesAppSynchronize(GFLicenseDomain)) {
        if (error) *error = GFLicenseError(@"Unable to save license");
        return NO;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.kulinich.glassfolders/preferenceschanged"), NULL, NULL, true);
    return YES;
}

// A short-lived, nonexportable Secure Enclave key proves possession of the
// response key. This is not an Apple hardware attestation. The runtime license
// check independently re-reads the hardware identity in both host processes.
static inline NSString *GFLicenseCreateProof(NSString *challenge, NSError **error) {
    NSString *reason = @"Invalid binding challenge";
    do {
        if (![challenge isKindOfClass:NSString.class] || challenge.length > 2048) break;
        id c = [NSJSONSerialization JSONObjectWithData:[challenge dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if (![c isKindOfClass:NSDictionary.class]) break;
        NSSet *fields = [NSSet setWithArray:@[@"type", @"v", @"nonce", @"device", @"issued", @"expires"]];
        if (![[NSSet setWithArray:[c allKeys]] isEqual:fields] || ![c[@"type"] isEqual:@"GFC1"] ||
            ![c[@"v"] isKindOfClass:NSNumber.class] || ![c[@"v"] isEqual:@1] ||
            !GFLicenseMatches(c[@"nonce"], @"^[A-F0-9]{64}$") ||
            !GFLicenseMatches(c[@"device"], @"^GF-[A-F0-9]{64}$") ||
            ![c[@"issued"] isKindOfClass:NSNumber.class] || ![c[@"expires"] isKindOfClass:NSNumber.class]) break;
        long long issued = [c[@"issued"] longLongValue], expires = [c[@"expires"] longLongValue];
        NSString *canonical = [NSString stringWithFormat:@"{\"type\":\"GFC1\",\"v\":1,\"nonce\":\"%@\",\"device\":\"%@\",\"issued\":%lld,\"expires\":%lld}",
                               c[@"nonce"], c[@"device"], issued, expires];
        if (![canonical isEqual:challenge]) break;
        reason = @"Binding challenge expired";
        long long now = (long long)NSDate.date.timeIntervalSince1970;
        if (issued < 0 || issued > now + 60 || expires <= now || expires <= issued || expires > issued + 900) break;
        reason = @"Binding challenge is for another device";
        NSString *device = GFLicenseDeviceCode();
        if (!device.length || ![c[@"device"] isEqual:device]) break;
        reason = @"Secure Enclave device proof unavailable";
        SecAccessControlRef access = SecAccessControlCreateWithFlags(NULL,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAccessControlPrivateKeyUsage, NULL);
        if (!access) break;
        NSDictionary *attrs = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeySizeInBits: @256,
            (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
            (__bridge id)kSecPrivateKeyAttrs: @{
                (__bridge id)kSecAttrIsPermanent: @NO,
                (__bridge id)kSecAttrAccessControl: (__bridge id)access
            }
        };
        SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, NULL);
        CFRelease(access);
        if (!privateKey) break;
        SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
        NSData *point = publicKey ? CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, NULL)) : nil;
        if (publicKey) CFRelease(publicKey);
        if (point.length != 65) { CFRelease(privateKey); break; }
        NSString *hash = GFLicenseSHA256([challenge dataUsingEncoding:NSUTF8StringEncoding]);
        NSString *unsignedProof = [NSString stringWithFormat:
            @"{\"type\":\"GFP1\",\"v\":1,\"challenge_hash\":\"%@\",\"device\":\"%@\",\"public_key\":\"%@\"}",
            hash, device, GFLicenseEncode(point)];
        NSData *message = [[@"GlassFolders-GFP1-v1\n" stringByAppendingString:unsignedProof] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *signature = CFBridgingRelease(SecKeyCreateSignature(privateKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message, NULL));
        CFRelease(privateKey);
        if (!signature.length) break;
        return [[unsignedProof substringToIndex:unsignedProof.length - 1] stringByAppendingFormat:
                @",\"signature\":\"%@\"}", GFLicenseEncode(signature)];
    } while (NO);
    if (error) *error = GFLicenseError(reason);
    return nil;
}
