"""Blur-only wiring plus native production math/cache tests when supported."""

from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def method(source, signature):
    start = source.index(signature + " {")
    end = source.index("\n}", start) + 2
    return source[start:end]


class NotificationBlurTests(unittest.TestCase):
    def test_slider_and_preference_contract(self):
        items = plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())["items"]
        sliders = [item for item in items if item.get("key") == "NotificationBlur"]
        self.assertEqual(len(sliders), 1)
        slider = sliders[0]
        for key, value in {"cell": "PSSliderCell", "cellClass": "GFPercentSliderCell",
                           "default": 50, "min": 0, "max": 100,
                           "defaults": "com.kulinich.glassfolders",
                           "PostNotification": "com.kulinich.glassfolders/preferenceschanged"}.items():
            self.assertEqual(slider[key], value, key)
        self.assertNotIn("gfSection", slider)
        self.assertNotIn("gfStyle", slider)
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertIn('GFReadPercent(CFSTR("NotificationBlur"), 50.0)', tweak)
        self.assertIn("static CGFloat GFNotificationBlurAmount = 0.5;", tweak)
        for locale in ("en", "zh-Hans"):
            text = (ROOT / f"prefs/Resources/{locale}.lproj/Root.strings").read_text(encoding="utf-8")
            self.assertRegex(text, re.compile(r'^"Notification Blur" = "[^"]+";', re.M), locale)

    def test_cached_refresh_and_zero_blur(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        refresh = method(lock, "- (void)gfRefreshBackdropBlurIfNeeded")
        self.assertLess(refresh.index("self.gfAppliedBackdropBlurRadius == radius"),
                        refresh.index("GFLockApplyBackdropRecipe"))
        self.assertIn("self.gfHasBackdropBlurRadius = YES", refresh)
        self.assertIn("GFNotificationBlurScale(GFNotificationBlurAmount)", refresh)
        self.assertNotIn("gfRefreshMaterial", refresh)
        for forbidden in ("gfBodyVeil", "gfLockRim", "textColor", "gfTintView"):
            self.assertNotIn(forbidden, refresh)
        full = method(lock, "- (void)gfRefreshMaterial")
        self.assertLess(full.index("[super gfRefreshMaterial]"), full.index("self.gfHasBackdropBlurRadius = NO"))
        self.assertIn("if (blur && radius > 0.001)", lock)
        self.assertIn("if (notification) [glass gfRefreshBackdropBlurIfNeeded];", lock)
        self.assertNotIn("CFPreferences", lock)
        self.assertNotIn("CADisplayLink", lock)

    def test_scope_and_live_reload_are_preserved(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        notification = (ROOT / "GFNotificationGlassView.h").read_text(encoding="utf-8")
        self.assertIn("return NO;", method(lock, "- (BOOL)gfUsesNotificationBlurControl"))
        banner = lock.split("@implementation GFBannerGlassView", 1)[1]
        self.assertIn("return YES;", method(banner, "- (BOOL)gfUsesNotificationBlurControl"))
        self.assertIn("return YES;", method(notification, "- (BOOL)gfUsesNotificationBlurControl"))
        stack = method(notification, "- (void)gfRefreshStackAppearance")
        self.assertNotIn("Backdrop", stack)
        self.assertNotIn("Blur", stack)
        prelude = (ROOT / "GFLivePreferencesPrelude.h").read_text(encoding="utf-8")
        self.assertIn("GFLoadPreferences();", prelude)
        self.assertIn("GFUpdateLockScreenSurface(view);", prelude)
        self.assertIn("Coalesce rapid slider writes", prelude)

    @unittest.skipUnless(shutil.which("cc") or shutil.which("clang"), "No local C compiler")
    def test_native_math(self):
        compiler = shutil.which("cc") or shutil.which("clang")
        with tempfile.TemporaryDirectory(prefix="gf-notification-blur-") as directory:
            binary = Path(directory) / ("blur.exe" if sys.platform == "win32" else "blur")
            subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
                            str(ROOT / "tests/test_notification_blur.c"), "-lm", "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("clang"), "Requires macOS Foundation")
    def test_native_production_cache(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        notification = (ROOT / "GFNotificationGlassView.h").read_text(encoding="utf-8")
        selected = "\n".join(method(lock, signature) for signature in (
            "- (CGFloat)gfBackdropBlurRadius", "- (BOOL)gfUsesNotificationBlurControl",
            "- (void)gfRefreshBackdropBlurIfNeeded",
            "- (void)gfApplyNotificationPalette:(GFNotificationPalette)palette",
            "- (void)gfClearNotificationPalette"))
        opt_in = method(notification, "- (BOOL)gfUsesNotificationBlurControl")
        harness = r'''
#import <Foundation/Foundation.h>
#import "GFNotificationBlur.h"
#import "GFNotificationPalette.h"
static const CGFloat GFLockCardBlurRadius = 8, GFNotificationLightBlurRadius = 3,
    GFNotificationDarkBlurRadius = 4;
static CGFloat GFNotificationBlurAmount = 0.5;
@interface TestRim : NSObject
@property BOOL gfLightSurface;
- (void)setNeedsLayout;
@end
@implementation TestRim
- (void)setNeedsLayout {}
@end
@interface TestFallback : NSObject
@property CGFloat alpha;
@end
@implementation TestFallback
@end
@interface GFLockScreenGlassView : NSObject
@property BOOL gfUsesNotificationPalette;
@property BOOL gfHasBackdropBlurRadius;
@property CGFloat gfAppliedBackdropBlurRadius;
@property GFNotificationPalette gfNotificationPalette;
@property (strong) TestRim *gfLockRim;
@property (strong) TestFallback *gfFallbackBlurView;
@property NSUInteger recipeWrites;
- (CGFloat)gfBackdropBlurRadius;
- (BOOL)gfUsesNotificationBlurControl;
- (void)gfRefreshBackdropBlurIfNeeded;
- (void)gfApplyNotificationPalette:(GFNotificationPalette)palette;
- (void)gfClearNotificationPalette;
@end
static void GFLockApplyBackdropRecipe(GFLockScreenGlassView *glass, NSString *group, CGFloat radius) {
    (void)group; (void)radius; glass.recipeWrites++;
}
@implementation GFLockScreenGlassView
- (NSString *)gfBackdropGroupName { return @"test"; }
- (void)gfRefreshBodyVeil {}
/* PRODUCTION_METHODS */
@end
@interface TestNotification : GFLockScreenGlassView
@end
@implementation TestNotification
/* PRODUCTION_OPT_IN */
@end
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #x); return 1; } } while (0)
int main(void) {
    @autoreleasepool {
        TestNotification *glass = [TestNotification new];
        glass.gfLockRim = [TestRim new];
        glass.gfFallbackBlurView = [TestFallback new];
        GFNotificationPalette dark = GFNotificationPaletteForWallpaper(0,0,0,1,false,false);
        GFNotificationPalette light = GFNotificationPaletteForWallpaper(1,1,1,1,false,false);
        [glass gfApplyNotificationPalette:dark];
        CHECK(glass.gfAppliedBackdropBlurRadius == 4 && glass.recipeWrites == 1);
        for (NSUInteger i = 0; i < 400; i++) [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.recipeWrites == 1);
        GFNotificationBlurAmount = 0;
        [glass gfApplyNotificationPalette:dark];
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 0 && glass.recipeWrites == 2);
        CHECK(glass.gfFallbackBlurView.alpha == 0);
        GFNotificationBlurAmount = 1;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 8 && glass.recipeWrites == 3);
        [glass gfApplyNotificationPalette:light];
        CHECK(glass.gfAppliedBackdropBlurRadius == 6 && glass.gfLockRim.gfLightSurface);
        CHECK(glass.gfNotificationPalette.bodyWhite == light.bodyWhite);
        [glass gfClearNotificationPalette];
        CHECK(glass.gfAppliedBackdropBlurRadius == 16 && !glass.gfLockRim.gfLightSurface);
        GFNotificationBlurAmount = 0.5;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 8);
        [glass gfApplyNotificationPalette:light];
        CHECK(glass.gfAppliedBackdropBlurRadius == 3);
        NSUInteger writes = glass.recipeWrites;
        glass.gfHasBackdropBlurRadius = NO;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.recipeWrites == writes + 1);
        GFLockScreenGlassView *music = [GFLockScreenGlassView new];
        GFNotificationBlurAmount = 0;
        CHECK([music gfBackdropBlurRadius] == 8);
        GFNotificationBlurAmount = 1;
        CHECK([music gfBackdropBlurRadius] == 8);
        puts("Production blur methods: retained cards, cache, zero, fallback, palette, app transition and scope PASS");
    }
    return 0;
}
'''
        harness = harness.replace("/* PRODUCTION_METHODS */", selected).replace("/* PRODUCTION_OPT_IN */", opt_in)
        with tempfile.TemporaryDirectory(prefix="gf-notification-cache-") as directory:
            source = Path(directory) / "cache.m"
            binary = Path(directory) / "cache"
            source.write_text(harness, encoding="utf-8")
            subprocess.run(["clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT),
                            "-framework", "Foundation", str(source), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
