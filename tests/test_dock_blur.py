"""Dock-only preference/scope guards; production execution is in the macOS harness."""

from pathlib import Path
import hashlib
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockBlurTests(unittest.TestCase):
    def test_independent_slider_and_live_reload(self):
        items = plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())["items"]
        sliders = [item for item in items if item.get("key") == "DockBlur"]
        self.assertEqual(len(sliders), 1)
        slider = sliders[0]
        for key, expected in {"cell": "PSSliderCell", "cellClass": "GFPercentSliderCell",
                              "min": 0, "max": 100, "default": 50,
                              "defaults": "com.kulinich.glassfolders",
                              "PostNotification": "com.kulinich.glassfolders/preferenceschanged"}.items():
            self.assertEqual(slider[key], expected, key)
        self.assertNotIn("gfSection", slider)
        self.assertNotIn("gfStyle", slider)
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn('GFDockBlurAmount = GFReadPercent(CFSTR("DockBlur"), 50.0)', tweak)
        self.assertIn("static CGFloat GFDockBlurAmount = 0.5", tweak)
        self.assertIn("if (GFDockMode == 1)", tweak)
        for locale in ("en", "zh-Hans"):
            strings = (ROOT / f"prefs/Resources/{locale}.lproj/Root.strings").read_text(encoding="utf-8")
            self.assertRegex(strings, re.compile(r'^"Dock Blur" = "[^"]+";', re.M))
        live = (ROOT / "GFLivePreferencesPrelude.h").read_text(encoding="utf-8")
        self.assertIn("GFUpdateDockBackground(view)", live)

    def test_cache_zero_blur_and_original_rim(self):
        library = (ROOT / "GFAppLibraryGlass.h").read_text(encoding="utf-8")
        self.assertIn("self.gfMaterialDockBlurAmount == dockBlur", library)
        self.assertIn("isfinite(GFDockBlurAmount)", library)
        self.assertIn("hasNativeMaterial = recipe.blur <= 0.001", library)
        self.assertIn("self.gfDockVariant ? 0.44 * dockBlur", library)
        self.assertIn("self.gfCardRim.hidden = adaptiveLight && !self.gfDockVariant", library)
        self.assertIn("self.gfAdaptiveRim.hidden = !adaptiveLight || self.gfDockVariant", library)
        self.assertNotIn("GFNotificationBlurAmount", library)
        for token in ("CFPreferences", "CADisplayLink", "NSTimer", "takeScreenshot"):
            self.assertNotIn(token, library)
        # No edge renderer changes accompany the Dock material adjustment.
        rim = (ROOT / "GFHorizontalGlassRim.h").read_text(encoding="utf-8")
        self.assertEqual(hashlib.sha256(rim.encode()).hexdigest(),
                         "7b1f05343a5108385236ba1187c970488fa0e2d28f29888f16ed6dd96be50c3c")


if __name__ == "__main__":
    unittest.main()
