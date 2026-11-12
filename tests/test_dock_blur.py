"""Shared Home/Dock strength guards; production execution is in the macOS harness."""

from pathlib import Path
import hashlib
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockBlurTests(unittest.TestCase):
    def test_shared_slider_and_live_reload(self):
        items = plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())["items"]
        sliders = [x for x in items if x.get("cellClass") == "GFPercentSliderCell"]
        self.assertEqual({x["key"] for x in sliders}, {"ClearStrength", "LiquidGlassStrength"})
        self.assertFalse(any(x.get("key") in {"DockBlur", "NotificationBlur"} for x in items))
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertNotIn("GFDockBlurAmount", tweak)
        self.assertIn("if (GFDockMode == 1)", tweak)
        self.assertIn("(GFStyle == 0) ? GFClearStrength : GFLiquidGlassStrength", tweak)
        live = (ROOT / "GFLivePreferencesPrelude.h").read_text(encoding="utf-8")
        self.assertIn("GFUpdateDockBackground(view)", live)
        self.assertIn("GFUpdateLockScreenSurface(view)", live)

    def test_cache_zero_blur_and_original_rim(self):
        library = (ROOT / "GFAppLibraryGlass.h").read_text(encoding="utf-8")
        self.assertIn("self.gfMaterialGlassAmount == amount", library)
        self.assertIn("GFSharedGlassAmount(GFGlassStrength)", library)
        self.assertIn("recipe.blur *= GFSharedGlassScale(amount)", library)
        self.assertIn("hasNativeMaterial = recipe.blur <= 0.001", library)
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
