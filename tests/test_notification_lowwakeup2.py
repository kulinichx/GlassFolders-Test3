"""Source provenance and notification integration boundaries, not visual QA."""
from pathlib import Path
import hashlib
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.3.1~lowwakeup2+whitebg2"
BASELINE = {
    "GFLivePreferencesPrelude.h": "a264e6bc2d97c05b70395cceb2855e79a099ac242a131d0300854e5dc215b988",
    "prefs/GFRootListController.m": "442ce9593397c785140ff90bb15b7f3830029b5006d4d6343f9e1e39ee0491c3",
    "Makefile": "38b92b58065d3c8e08518f8378cf1b50ca492f9608d92bc74a98e3fac41c5b17",
    "GFLicensePublicKey.h": "28aeae09e8717c64e5762ac2b9e708a3bf15c674787d6bdf0f12c8a26a56bdb9",
}


class NotificationIntegration(unittest.TestCase):
    def test_installed_version_baseline(self):
        for name, expected in BASELINE.items():
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), expected, name)
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        stripped, count = re.subn(
            r"^[ \t]*// GF_NOTIFICATION_WHITEBG2_BEGIN\n.*?"
            r"^[ \t]*// GF_NOTIFICATION_WHITEBG2_END\n",
            "", tweak, flags=re.S | re.M,
        )
        self.assertEqual(count, 3)
        self.assertEqual(hashlib.sha256(stripped.encode()).hexdigest(),
                         "9e9f944efd9e06577f3830dd9b2858ccfd6618a67468adf5b5ed835db2fcf9c2")

    def test_candidate_identity(self):
        control = (ROOT / "control").read_text(encoding="utf-8")
        self.assertIn("Version: " + VERSION + "\n", control)
        self.assertIn("Architecture: iphoneos-arm64e", control)
        info = plistlib.loads((ROOT / "prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleVersion"], "1.3.1.3")
        self.assertEqual(info["CFBundleShortVersionString"], "1.3.1")
        self.assertEqual(info["CFBundleIdentifier"], "com.kulinich.glassfolders.preferences")

    def test_scene_scope_and_low_wakeup(self):
        foreground = (ROOT / "GFNotificationForeground.h").read_text(encoding="utf-8")
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn("adaptiveNotification = notification && !banner", lock)
        self.assertIn("averageColorForCurrentWallpaper", foreground)
        self.assertIn("GFNotificationWallpaperGeneration", foreground)
        self.assertIn("self.wallpaperProvider == provider", foreground)
        self.assertNotIn("userInterfaceStyle", foreground)
        self.assertNotRegex(tweak, r"%hook\s+(?:UILabel|UIView|UITextView)\b")
        for name in ("CADisplayLink", "NSTimer", "drawViewHierarchy", "takeScreenshot"):
            self.assertNotIn(name, foreground)
        self.assertIn("if (body) [state.foreground applyToHost:node content:body]", lock)
        self.assertIn("GFNotificationHasVoidMethod", tweak)

    def test_restoration_and_slots(self):
        text = (ROOT / "GFNotificationForeground.h").read_text(encoding="utf-8")
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        for name in ("nativeAttributedText", "nativeColor", "nativeFilters",
                     "nativeCompositingFilter", "_primaryTextLabel", "_secondaryTextElement",
                     "_dateLabel", "_headerContentView"):
            self.assertIn(name, text)
        self.assertIn("[self.foreground restore]", lock)
        self.assertIn("UIAccessibilityIsReduceTransparencyEnabled()", lock)
        self.assertIn("UIAccessibilityDarkerSystemColorsEnabled()", lock)
        self.assertNotIn("GFNotificationContrast", lock)
        self.assertNotIn("gfNotificationVeilOpacity", lock)

    def test_build_resources(self):
        makefile = (ROOT / "prefs/Makefile").read_text(encoding="utf-8")
        resources = next(line for line in makefile.splitlines()
                         if line.startswith("GlassFoldersPrefs_RESOURCE_FILES"))
        for name in resources.split("=", 1)[1].split():
            self.assertTrue((ROOT / "prefs" / name).is_file(), name)


if __name__ == "__main__":
    unittest.main()
