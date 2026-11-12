"""Source provenance and notification integration boundaries, not visual QA."""
from pathlib import Path
import hashlib
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.3.4"
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
        stripped, count = re.subn(
            r"^[ \t]*// GF_LIBRARY_LEGIBILITY_BEGIN\n.*?"
            r"^[ \t]*// GF_LIBRARY_LEGIBILITY_END\n",
            "", stripped, flags=re.S | re.M,
        )
        self.assertEqual(count, 7)
        stripped, count = re.subn(
            r"^[ \t]*// GF_NOTIFICATION_BLUR_BEGIN\n.*?"
            r"^[ \t]*// GF_NOTIFICATION_BLUR_END\n\n",
            "", stripped, flags=re.S | re.M,
        )
        self.assertEqual(count, 2)
        self.assertEqual(hashlib.sha256(stripped.encode()).hexdigest(),
                         "9e9f944efd9e06577f3830dd9b2858ccfd6618a67468adf5b5ed835db2fcf9c2")

    def test_candidate_identity(self):
        control = (ROOT / "control").read_text(encoding="utf-8")
        self.assertIn("Version: " + VERSION + "\n", control)
        self.assertIn("Architecture: iphoneos-arm64e", control)
        info = plistlib.loads((ROOT / "prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleVersion"], "1.3.4.1")
        self.assertEqual(info["CFBundleShortVersionString"], VERSION)
        self.assertEqual(info["CFBundleIdentifier"], "com.kulinich.glassfolders.preferences")
        self.assertEqual(info["CFBundleDisplayName"], "Luma Glass")
        entry = plistlib.loads((ROOT / "layout/Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist").read_bytes())
        self.assertEqual(entry["entry"]["label"], "Luma Glass")
        self.assertEqual(entry["entry"]["bundle"], "GlassFoldersPrefs")
        self.assertIn("Name: Luma Glass\n", control)

    def test_scene_scope_and_low_wakeup(self):
        foreground = (ROOT / "GFNotificationForeground.h").read_text(encoding="utf-8")
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn("adaptiveNotification = notification && (!banner || homeBanner)", lock)
        self.assertIn("GFHomeScreenVisible()", lock)
        self.assertIn("[self gfBackdropGroupName]", lock)
        self.assertIn("averageColorForCurrentWallpaper", foreground)
        self.assertIn("GFNotificationWallpaperGeneration", foreground)
        self.assertIn("self.wallpaperProvider == provider", foreground)
        self.assertNotIn("userInterfaceStyle", foreground)
        self.assertNotRegex(tweak, r"%hook\s+(?:UILabel|UIView|UITextView)\b")
        for name in ("CADisplayLink", "NSTimer", "drawViewHierarchy", "takeScreenshot"):
            self.assertNotIn(name, foreground)
        self.assertIn("if (body) [state.foreground applyToHost:node content:body]", lock)
        self.assertIn("GFNotificationHasVoidMethod", tweak)
        self.assertEqual(tweak.count("- (void)_updateTextAttributesForDateLabel"), 2)
        self.assertIn("%init(GFNotificationSeamlessDateAttributesHooks)", tweak)
        self.assertIn("%init(GFNotificationHeaderDateAttributesHooks)", tweak)
        home = (ROOT / "GFHomeScreenPalette.h").read_text(encoding="utf-8")
        library = (ROOT / "GFAppLibraryGlass.h").read_text(encoding="utf-8")
        self.assertIn('@"averageColorForVariant:"', home)
        self.assertIn("GFHomeWallpaperGeneration", home)
        self.assertIn("if (!self.gfDockVariant) palette = GFHomeWallpaperPalette", library)
        self.assertIn("self.gfCardRim.hidden = adaptiveLight", library)

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

    def test_notification_blur_candidate_scope(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        radii = dict(re.findall(
            r"static const CGFloat (GF\w+BlurRadius) = (\d+\.\d+);", lock))
        self.assertEqual(radii, {
            "GFLockCardBlurRadius": "8.0",
            "GFNotificationLightBlurRadius": "3.0",
            "GFNotificationDarkBlurRadius": "4.0",
            "GFLockButtonBlurRadius": "3.0",
        })
        recipe = re.search(r"- \(CGFloat\)gfBackdropBlurRadius \{([^}]+)\}", lock)
        self.assertIsNotNone(recipe)
        self.assertEqual(" ".join(recipe[1].split()),
            "CGFloat radius = !self.gfUsesNotificationPalette ? GFLockCardBlurRadius : "
            "(self.gfNotificationPalette.lightSurface ? "
            "GFNotificationLightBlurRadius : GFNotificationDarkBlurRadius); "
            "return [self gfUsesNotificationBlurControl] ? "
            "radius * GFNotificationBlurScale(GFNotificationBlurAmount) : radius;")
        for name in ("gfRefreshMaterial", "gfClearNotificationPalette"):
            body = re.search(r"- \(void\)" + name + r" \{(.*?)\n\}", lock, re.S)
            self.assertIsNotNone(body)
            self.assertIn("[self gfRefreshBackdropBlurIfNeeded]", body[1])
        apply = re.search(
            r"- \(void\)gfApplyNotificationPalette:\(GFNotificationPalette\)palette \{(.*?)\n\}",
            lock, re.S)
        self.assertIsNotNone(apply)
        self.assertIn("if (backdropChanged)", apply[1])
        self.assertIn("[self gfRefreshBackdropBlurIfNeeded]", apply[1])
        self.assertLess(apply[1].index("self.gfNotificationPalette = palette"),
                        apply[1].index("[self gfRefreshBackdropBlurIfNeeded]"))
        clear = re.search(r"- \(void\)gfClearNotificationPalette \{(.*?)\n\}", lock, re.S)[1]
        self.assertLess(clear.index("self.gfUsesNotificationPalette = NO"),
                        clear.index("[self gfRefreshBackdropBlurIfNeeded]"))

    def test_blur_candidate_preserves_decoration_and_palette(self):
        expected = {
            "GFGlassRim.h": "534037542d6d6b6f0c9c5ab4143978e2984ac28bbb754de5d1d49b3d7d384fa0",
            "GFNotificationPalette.h": "fb12d35d38c24b926fed753396438f575d16d22515fd5d35127c9830d298f80e",
        }
        for name, digest in expected.items():
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), digest, name)

    def test_library_native_legibility(self):
        library = (ROOT / "GFLibraryLegibility.h").read_text(encoding="utf-8")
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn("return GFLibraryHomeLegibility(traits) ?: native", library)
        self.assertIn('@"_currentHomeScreenLegibilitySettings"', library)
        self.assertIn('@"legibilitySettingsForVariant:"', library)
        self.assertIn('objc_getClass("_UILegibilitySettings")', library)
        self.assertIn("GFLibraryRefreshSearchTree(searchView, NO)", tweak)
        self.assertIn("GFLibraryRefreshSearchTree(candidate, YES)", tweak)
        self.assertIn("GFLibraryRefreshControllerLegibility(controller)", tweak)
        self.assertIn("%init(GFLibraryNativeLegibilityHooks)", tweak)
        self.assertIn("%init(GFLibrarySearchAppearanceHooks)", tweak)
        self.assertIn("GFLibraryEffectiveLegibility(native, self.traitCollection)", tweak)
        for forbidden in ("setTextColor", "attributedText =", "setFilters",
                          "setTintColor", "CADisplayLink", "NSTimer", "takeScreenshot",
                          "averageColorForVariant:", "colorWithWhite:"):
            self.assertNotIn(forbidden, library)
        self.assertIn("state.generation == GFHomeWallpaperGeneration", library)
        self.assertIn("current == state.appliedStyle", library)

    def test_build_resources(self):
        makefile = (ROOT / "prefs/Makefile").read_text(encoding="utf-8")
        resources = next(line for line in makefile.splitlines()
                         if line.startswith("GlassFoldersPrefs_RESOURCE_FILES"))
        for name in resources.split("=", 1)[1].split():
            self.assertTrue((ROOT / "prefs" / name).is_file(), name)


if __name__ == "__main__":
    unittest.main()
