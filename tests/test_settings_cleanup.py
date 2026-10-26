#!/usr/bin/env python3
"""Regression: iOS 16 stable UI hides inactive/debug optics toggles.

Retire UI and old saved values; do not delete the old rendering code.
"""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
prefs = plistlib.loads((root / 'prefs/Resources/Root.plist').read_bytes())
items = prefs['items']
retired = {
    'AppLibraryNativeLiveGlassEnabled',
    'AppLibraryLensMaterialEnabled',
    'AppLibraryBlurDiagnosticsEnabled',
    'AppleLiquidMaterialEnabled',
    'FolderNativeRefractionEnabled',
    'FolderChromaticRimEnabled',
    'FolderChromaticRimIntensity',
    'DockLensMaterialEnabled',
}
assert not ({x.get('key') for x in items} & retired)
expected = {
    'Enabled', 'AppLibraryGlassEnabled', 'DockEnabled',
    'BannerNotificationsEnabled', 'LockNotificationsEnabled',
    'LockQuickActionsEnabled', 'LockMusicEnabled', 'LockActivitiesEnabled',
    'ClearStrength', 'LiquidGlassStrength', 'DockMode',
}
assert expected <= {x.get('key') for x in items}
tweak = (root / 'Tweak.xm').read_text()
for assignment in (
    'GFNativeLiveGlassEnabled = NO;',
    'GFAppLibraryBlurDiagnosticsEnabled = NO;',
    'GFAppleLiquidMaterialEnabled = NO;',
    'GFAppLibraryLensMaterialEnabled = NO;',
    'GFExperimentalChromaticRimEnabled = NO;',
    'GFFolderNativeRefractionEnabled = NO;',
):
    assert assignment in tweak, assignment
# Dock's older 4pt clear-glass recipe was visually accepted; retiring the
# settings row must not silently force Dock back to the 10pt blur recipe.
assert 'GFDockLensMaterialEnabled = licensed && GFDockEnabled && GFDockMode == 1;' in tweak
for key in retired:
    assert f'CFSTR("{key}")' not in tweak, key
for loc in ('en.lproj', 'zh-Hans.lproj'):
    strings = (root / 'prefs/Resources' / loc / 'Root.strings').read_text()
    for label in (
        'Native Live Refraction (Requires Engine)',
        'App Library Clear Lens (Beta)',
        'App Library Blur Diagnostics (V4)',
        'iOS 27 Inspired Glass (Beta)',
        'Folder Live Refraction Bridge (Requires Engine)',
        'Folder Chromatic Rim (Experimental)',
        'Chromatic Rim Intensity',
        'Dock Clear Lens (Beta)',
    ):
        assert f'"{label}"' not in strings, (loc, label)
print('iOS16 stable settings cleanup: PASS')
