#!/usr/bin/env python3
"""Reject a relabeled old baseline as well as a mislabeled candidate."""
from pathlib import Path
import hashlib
import plistlib

root = Path(__file__).resolve().parents[1]
control = dict(
    line.split(": ", 1)
    for line in (root / "control").read_text(encoding="utf-8").splitlines()
    if ": " in line
)
info = plistlib.loads((root / "prefs/Resources/Info.plist").read_bytes())
workflow = (root / ".github/workflows/build.yml").read_text(encoding="utf-8")

assert control["Package"] == "com.kulinich.glassfolders"
assert control["Name"] == "GlassFolders (1.3.2 WhiteBG Test 1)"
assert control["Version"] == "1.3.2+whitebg1"
assert control["Architecture"] == "iphoneos-arm64e"
assert info["CFBundleIdentifier"] == "com.kulinich.glassfolders.preferences"
assert info["CFBundleShortVersionString"] == "1.3.2"
assert info["CFBundleVersion"] == "1.3.2.2"
assert info["CFBundleDisplayName"] == "GlassFolders 1.3.2 WhiteBG Test 1"
assert workflow.count("^Version: 1.3.2+whitebg1$") == 2
assert workflow.count("needs: notification-contrast") == 2
assert workflow.count("runs-on: macos-15-intel") == 2
assert 'SHORT="packages/kulinich.glassfolders_1.3.2+whitebg1.deb"' in workflow

# Text hashes from the verified 1.3.2 commit e4c3e77, normalized for CRLF.
baseline = {
    "GFLivePreferencesPrelude.h": "23eb3a5ac041813008575cfbfa2570525a06d61399bb6dcb34a076a728805c2a",
    "prefs/GFRootListController.m": "c26f095315cf37d424da3029126c4e59c2cc3b0312df4a8a95cbb19af4dedd04",
    "prefs/Makefile": "1c6773c7d097fc04539cd742bc2e4ca3da7f630913ea21320feeedcdcafc8ca9",
    "Makefile": "38b92b58065d3c8e08518f8378cf1b50ca492f9608d92bc74a98e3fac41c5b17",
    "GFLicensePublicKey.h": "28aeae09e8717c64e5762ac2b9e708a3bf15c674787d6bdf0f12c8a26a56bdb9",
}
for name, expected in baseline.items():
    text = (root / name).read_text(encoding="utf-8")
    assert hashlib.sha256(text.encode("utf-8")).hexdigest() == expected, name

# The complete main implementation must be 1.3.2 plus only these two additions.
tweak = (root / "Tweak.xm").read_text(encoding="utf-8")
trait_hook = """- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    GFUpdateLockScreenSurface((UIView *)self);
}
"""
observers = """            for (NSString *name in @[UIAccessibilityReduceTransparencyStatusDidChangeNotification,
                                     UIAccessibilityDarkerSystemColorsStatusDidChangeNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil
                    queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                        GFLockScheduleRefresh();
                    }];
            }
"""
for addition in (trait_hook, observers):
    assert tweak.count(addition) == 1
    tweak = tweak.replace(addition, "", 1)
assert hashlib.sha256(tweak.encode("utf-8")).hexdigest() == (
    "b98b3a43eb1a2d41301b1053f81fd505fbdc28b484427729e60f0703836140a2"
), "Main implementation diverged from the verified 1.3.2 baseline"
print("1.3.2 candidate identity, retained scheduler/settings/key and main source: PASS")
