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

    def test_owned_slider_has_disjoint_constraint_regions(self):
        source = (ROOT / "prefs/GFPercentSliderCell.m").read_text(encoding="utf-8")
        header = (ROOT / "prefs/GFPercentSliderCell.h").read_text(encoding="utf-8")
        self.assertIn("GFPercentSliderCell : PSTableCell", header)
        self.assertIn("[[UISlider alloc] initWithFrame:CGRectZero]", source)
        self.assertIn("label.backgroundColor = UIColor.clearColor", source)
        self.assertIn("[slider.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12]", source)
        self.assertIn("[label.widthAnchor constraintEqualToConstant:52]", source)
        self.assertIn("[slider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18]", source)
        self.assertIn("slider.translatesAutoresizingMaskIntoConstraints = NO", source)
        self.assertIn("if (self.gfOwnedSlider) return", source)
        self.assertNotIn("[self control]", source)
        self.assertIn("CFPreferencesSetAppValue", source)
        self.assertIn("UIControlEventValueChanged", source)

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("clang"), "Requires macOS Foundation/QuartzCore")
    def test_native_production_state_and_layout(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        source = (ROOT / "tests/notification_motion_harness.m").read_text(encoding="utf-8")
        source = source.replace("/* PRODUCTION_STACK_QUERY */", block(lock,
            "static BOOL GFLockNotificationIsStacked(UIView *host)"))
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
