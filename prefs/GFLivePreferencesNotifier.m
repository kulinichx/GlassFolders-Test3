#import "GFRootListController.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>

/*
 * PreferenceBundle -> SpringBoard live-update bridge.
 *
 * PSListController already performs the actual preference write. We only
 * synchronize the domain and broadcast a Darwin notification afterwards.
 */

static CFStringRef const GFLivePreferencesDomain =
    CFSTR("com.kulinich.glassfolders");

static CFStringRef const GFLivePreferencesChangedNotification =
    CFSTR("com.kulinich.glassfolders/preferenceschanged");

static void GFLivePostPreferencesChanged(void) {
    CFPreferencesAppSynchronize(GFLivePreferencesDomain);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        GFLivePreferencesChangedNotification,
        NULL,
        NULL,
        true
    );
}

@implementation GFRootListController (GFLivePreferencesNotifier)

- (void)setPreferenceValue:(id)value
                 specifier:(PSSpecifier *)specifier {
    /*
     * Preserve the Preferences framework's normal persistence path.
     * This covers switches, segmented controls and standard slider writes.
     */
    [super setPreferenceValue:value
                    specifier:specifier];

    GFLivePostPreferencesChanged();
}

@end
