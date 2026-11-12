"""Production layout/state regressions; native doubles are not UIKit visual QA."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    start = source.index(signature + " {")
    return source[start:source.index("\n}", start) + 2]


class NotificationMotionTests(unittest.TestCase):
    def test_stack_uses_content_state_not_animation_scale(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        query = block(lock, "static BOOL GFLockNotificationIsStacked(UIView *host)")
        self.assertIn('GFLockBool(host, @"isNotificationContentViewHidden", NO)', query)
        for token in (".transform", "hypot", "kGFLockStackedKey"):
            self.assertNotIn(token, query)
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertNotIn("GFLockTransformIsStacked", lock + tweak)
        self.assertNotIn("kGFLockStackedKey", lock + tweak)
        callback = block(tweak, "- (void)configureStackDimmingForTransform:(CGAffineTransform)transform")
        self.assertIn("%orig;", callback)
        self.assertIn("GFUpdateLockScreenSurface", callback)

    def test_slider_has_separate_coordinate_space_and_no_opaque_mask(self):
        source = (ROOT / "prefs/GFRootListController.m").read_text(encoding="utf-8")
        label = block(source, "- (void)gfEnsurePercentLabel")
        self.assertIn("label.backgroundColor = UIColor.clearColor", label)
        layout = block(source, "- (void)layoutSubviews")
        self.assertIn("[slider convertRect:slider.bounds toView:self.contentView]", layout)
        self.assertIn("[self.contentView convertRect:sliderFrame toView:slider.superview]", layout)
        self.assertIn("slider.clipsToBounds = NO", layout)
        self.assertIn("slider.layer.masksToBounds = NO", layout)
        self.assertNotIn("bringSubviewToFront", layout)
        self.assertNotIn("MAX(120.0", layout)

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("clang"), "Requires macOS Foundation/QuartzCore")
    def test_native_production_state_and_layout(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        prefs = (ROOT / "prefs/GFRootListController.m").read_text(encoding="utf-8")
        source = (ROOT / "tests/notification_motion_harness.m").read_text(encoding="utf-8")
        source = source.replace("/* PRODUCTION_STACK_QUERY */", block(lock,
            "static BOOL GFLockNotificationIsStacked(UIView *host)"))
        source = source.replace("/* PRODUCTION_SLIDER_LAYOUT */", block(prefs, "- (void)layoutSubviews"))
        with tempfile.TemporaryDirectory(prefix="gf-notification-motion-") as directory:
            path = Path(directory) / "motion.m"
            binary = Path(directory) / "motion"
            path.write_text(source, encoding="utf-8")
            subprocess.run(["clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                            "-framework", "Foundation", "-framework", "QuartzCore",
                            "-framework", "CoreGraphics",
                            str(path), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
