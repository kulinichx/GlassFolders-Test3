"""Integration guards; actual lifecycle/control checks run in the UIKit harness."""
from pathlib import Path
import unittest

from run_slider_uikit import production_function, surface_harness

ROOT = Path(__file__).resolve().parents[1]


class NotificationSurfaceTests(unittest.TestCase):
    def test_generated_uikit_harness_contains_actual_production_update(self):
        source = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        harness = surface_harness()
        for name in ("GFUpdateLockScreenSurface", "GFLockRefreshPlatterDecoration",
                     "GFLockSyncNotificationShadow", "GFLockSyncStackOverlay"):
            self.assertIn(production_function(source, f"static void {name}("), harness)
        self.assertNotIn("/* PRODUCTION_", harness)
        for key in ("kGFLockBackgroundKey", "kGFLockPressKey"):
            declaration = f"static char {key};"
            self.assertEqual(harness.count(declaration), 1)
            self.assertLess(harness.index(declaration),
                            harness.index("static void GFUpdateLockScreenSurface("))
        self.assertIn("GFTestGlassCreations == creations", harness)
        self.assertIn("target.selections == 2", harness)

    def test_decoration_hooks_are_specific_and_keep_native_setters(self):
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        for name in ("NCNotificationListStackDimmingOverlayView", "MTShadowView", "MTMaterialShadowView"):
            hook = tweak.split(f"%hook {name}\n", 1)[1].split("%end", 1)[0]
            self.assertIn("%orig(GFLockMaterialHiddenValue((UIView *)self, hidden))", hook)
        for name in ("UIView", "UIControl", "UILabel"):
            self.assertNotIn(f"%hook {name}\n", tweak)

    def test_swipe_buttons_share_system_recipe_and_live_refresh(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        prelude = (ROOT / "GFLivePreferencesPrelude.h").read_text(encoding="utf-8")
        self.assertIn('@"PLPlatterActionButton"', prelude)
        self.assertIn("enabled = GFLockNotificationsEnabled && GFLockNotificationSwipeContext(host)", lock)
        self.assertIn("GFSharedGlassScale(GFSystemGlassStrength)", lock)
        context = production_function(lock, "static BOOL GFLockNotificationSwipeContext(")
        self.assertIn("return actionContainer && notificationOwner", context)
        update = production_function(lock, "static void GFUpdateLockScreenSurface(")
        self.assertNotIn("addTarget:", update)
        self.assertNotIn("removeTarget:", update)
        self.assertIn("state.swipeTitle applyColor:", update)
        self.assertIn("swipeTintVisibility = GFLockSuppressDecoration", update)

    def test_date_color_is_scoped_and_matches_primary_text(self):
        foreground = (ROOT / "GFNotificationForeground.h").read_text(encoding="utf-8")
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn('GFLockIvar(content, "_dateLabel") secondary:NO', foreground)
        self.assertIn('GFLockIvar(header, "_dateLabel") secondary:NO', foreground)
        hook = tweak.split("%hook BSUIDefaultDateLabel\n", 1)[1].split("%end", 1)[0]
        self.assertIn("GFNotificationManagedDateColor", hook)
        self.assertIn("GFNotificationManagedDateText", hook)
        self.assertNotIn("%hook UILabel\n", tweak)
        self.assertIn("if (!state || state.applyingColor || !state.appliedColor) return color", foreground)


if __name__ == "__main__":
    unittest.main()
