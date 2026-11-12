"""Unified strength wiring plus native production math/cache tests."""

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
        sliders = [item for item in items if item.get("cellClass") == "GFPercentSliderCell"]
        self.assertEqual({x["key"] for x in sliders},
                         {"ClearStrength", "LiquidGlassStrength", "SystemGlassStrength"})
        for slider in sliders:
            for key, value in {"cell": "PSStaticTextCell", "default": 55, "min": 0, "max": 100,
                               "defaults": "com.kulinich.glassfolders"}.items():
                self.assertEqual(slider[key], value, key)
        self.assertFalse(any(x.get("key") in {"NotificationBlur", "DockBlur"} for x in items))
        tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
        self.assertNotIn("GFNotificationBlurAmount", tweak)
        self.assertIn("(GFStyle == 0) ? GFClearStrength : GFLiquidGlassStrength", tweak)
        self.assertIn("GFSystemGlassStrength =", tweak)
        for locale in ("en", "zh-Hans"):
            text = (ROOT / f"prefs/Resources/{locale}.lproj/Root.strings").read_text(encoding="utf-8")
            self.assertRegex(text, re.compile(r'^"Clear Strength" = "[^"]+";', re.M), locale)
            self.assertRegex(text, re.compile(r'^"System Glass Strength" = "[^"]+";', re.M), locale)

    def test_cached_refresh_and_zero_blur(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        refresh = method(lock, "- (void)gfRefreshBackdropBlurIfNeeded")
        self.assertLess(refresh.index("self.gfAppliedBackdropBlurRadius == radius"),
                        refresh.index("GFLockApplyBackdropRecipe"))
        self.assertIn("self.gfHasBackdropBlurRadius = YES", refresh)
        self.assertIn("GFSharedGlassScale(GFSystemGlassStrength)", refresh)
        self.assertNotIn("gfRefreshMaterial", refresh)
        for forbidden in ("gfBodyVeil", "gfLockRim", "textColor", "gfTintView"):
            self.assertNotIn(forbidden, refresh)
        full = method(lock, "- (void)gfRefreshMaterial")
        self.assertLess(full.index("[super gfRefreshMaterial]"), full.index("self.gfHasBackdropBlurRadius = NO"))
        self.assertIn("if (blur && radius > 0.001)", lock)
        self.assertIn("[glass gfRefreshBackdropBlurIfNeeded];", lock)
        self.assertNotIn("if (notification) [glass gfRefreshBackdropBlurIfNeeded];", lock)
        self.assertNotIn("CFPreferences", lock)
        self.assertNotIn("CADisplayLink", lock)

    def test_scope_and_live_reload_are_preserved(self):
        lock = (ROOT / "GFLockScreenGlass.h").read_text(encoding="utf-8")
        notification = (ROOT / "GFNotificationGlassView.h").read_text(encoding="utf-8")
        self.assertNotIn("gfUsesNotificationBlurControl", lock + notification)
        self.assertIn("return radius * GFSharedGlassScale(GFSystemGlassStrength)", lock)
        self.assertIn("return GFLockButtonBlurRadius * GFSharedGlassScale(GFSystemGlassStrength)", lock)
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
            "- (CGFloat)gfBackdropBlurRadius",
            "- (void)gfRefreshBackdropBlurIfNeeded",
            "- (void)gfApplyNotificationPalette:(GFNotificationPalette)palette",
            "- (void)gfClearNotificationPalette"))
        quick = lock.split("@implementation GFQuickActionGlassView", 1)[1]
        quick_methods = "\n".join(method(quick, signature) for signature in (
            "- (NSString *)gfBackdropGroupName", "- (CGFloat)gfBackdropBlurRadius",
            "- (void)gfRefreshBackdropBlurIfNeeded"))
        harness = r'''
#import <Foundation/Foundation.h>
#import "GFGlassStrength.h"
#import "GFNotificationPalette.h"
static const CGFloat GFLockCardBlurRadius = 8, GFNotificationLightBlurRadius = 3,
    GFNotificationDarkBlurRadius = 4, GFLockButtonBlurRadius = 3;
static CGFloat GFGlassStrength = 0.5;
#define GFSystemGlassStrength GFGlassStrength
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
@end
@interface TestButton : GFLockScreenGlassView
@end
@implementation TestButton
/* PRODUCTION_BUTTON_METHODS */
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
        GFGlassStrength = 0;
        [glass gfApplyNotificationPalette:dark];
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 0 && glass.recipeWrites == 2);
        CHECK(glass.gfFallbackBlurView.alpha == 0);
        GFGlassStrength = 1;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 8 && glass.recipeWrites == 3);
        [glass gfApplyNotificationPalette:light];
        CHECK(glass.gfAppliedBackdropBlurRadius == 6 && glass.gfLockRim.gfLightSurface);
        CHECK(glass.gfNotificationPalette.bodyWhite == light.bodyWhite);
        [glass gfClearNotificationPalette];
        CHECK(glass.gfAppliedBackdropBlurRadius == 16 && !glass.gfLockRim.gfLightSurface);
        GFGlassStrength = 0.5;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.gfAppliedBackdropBlurRadius == 8);
        [glass gfApplyNotificationPalette:light];
        CHECK(glass.gfAppliedBackdropBlurRadius == 3);
        NSUInteger writes = glass.recipeWrites;
        glass.gfHasBackdropBlurRadius = NO;
        [glass gfRefreshBackdropBlurIfNeeded];
        CHECK(glass.recipeWrites == writes + 1);
        GFLockScreenGlassView *music = [GFLockScreenGlassView new];
        GFGlassStrength = 0;
        [music gfRefreshBackdropBlurIfNeeded];
        CHECK([music gfBackdropBlurRadius] == 0 && music.recipeWrites == 1);
        GFGlassStrength = 1;
        [music gfRefreshBackdropBlurIfNeeded];
        CHECK([music gfBackdropBlurRadius] == 16 && music.recipeWrites == 2);
        TestButton *button = [TestButton new];
        button.gfFallbackBlurView = [TestFallback new];
        [button gfRefreshBackdropBlurIfNeeded];
        CHECK(button.gfAppliedBackdropBlurRadius == 6);
        CHECK(button.gfFallbackBlurView.alpha == 0.36);
        GFGlassStrength = 0;
        [button gfRefreshBackdropBlurIfNeeded];
        CHECK(button.gfAppliedBackdropBlurRadius == 0 && button.gfFallbackBlurView.alpha == 0);
        CHECK([[button gfBackdropGroupName] isEqualToString:@"com.kulinich.glassfolders.lock.buttons"]);
        puts("Production shared blur: retained cards, cache, zero, fallback, palette, banner, music/activity routing PASS");
    }
    return 0;
}
'''
        harness = harness.replace("/* PRODUCTION_METHODS */", selected).replace(
            "/* PRODUCTION_BUTTON_METHODS */", quick_methods)
        with tempfile.TemporaryDirectory(prefix="gf-notification-cache-") as directory:
            source = Path(directory) / "cache.m"
            binary = Path(directory) / "cache"
            source.write_text(harness, encoding="utf-8")
            subprocess.run(["clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT),
                            "-framework", "Foundation", str(source), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
