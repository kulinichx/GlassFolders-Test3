#!/usr/bin/env python3
"""Static UIKit integration checks, not device or compositing validation."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / "GFLockScreenGlass.h").read_text(encoding="utf-8")
tweak = (root / "Tweak.xm").read_text(encoding="utf-8")
rim = (root / "GFGlassRim.h").read_text(encoding="utf-8")

assert '#import "GFNotificationContrast.h"' in source
assert "alpha:0.35" not in source
assert "GFNotificationContrastForHost(host, background)" in source
assert "resolvedColorWithTraitCollection:traits" in source
assert "enumerateAttribute:NSForegroundColorAttributeName" in source
assert "if (label.highlighted) return NO;" in source
assert "alpha * opacity" in source
assert "if (view != host) opacity *= view.alpha;" in source
assert "view.layer.compositingFilter || view.layer.filters.count" in source
assert "[view isKindOfClass:UIVisualEffectView.class]) return NO;" in source
assert "NSUInteger remaining = 128;" in source
assert "depth > 10" in source
assert "contrast->samples >= 256" in source
assert "[view isKindOfClass:GFLockScreenGlassView.class]" in source

update = source[source.index("static void GFUpdateLockScreenSurface(UIView *host) {"):]
guard = update.index("(!notificationContentHidden && !contrast.valid)")
assert guard < update.index("state = [GFLockBackgroundState new]")
assert "if (state) GFRestoreLockScreenSurface(host);" in update[guard:guard + 180]
assert "UIAccessibilityIsReduceTransparencyEnabled()" in update
assert "UIAccessibilityDarkerSystemColorsEnabled()" in update
assert 'GFLockBool(host, @"isNotificationContentViewHidden", NO)' in update
assert "notification && !banner" in update
assert "gfConfigureNotificationContrast:contrast contentHidden:notificationContentHidden" in update
assert "if (self.gfNotificationSurface && !self.gfNotificationContentHidden)" in source
assert "self.gfLockRim.gfLightSurface = !contentHidden && contrast.lightSurface;" in source
assert "self.gfLockRim.gfSubdued || self.gfNotificationContentHidden" in source

# No global label hooks, recoloring, foreground filter removal, or new capture loop.
assert not re.search(r"(?:label|view)\.textColor\s*=", source)
assert "setTextColor:" not in source
assert "setFilters:nil" not in source
assert not re.search(r"%hook\s+(?:UILabel|UIView)\b", tweak)
for token in ("CADisplayLink", "drawViewHierarchy", "takeScreenshot", "NSTimer"):
    assert token not in source, token
assert "traitCollectionDidChange:(UITraitCollection *)previousTraitCollection" in tweak
assert "UIAccessibilityReduceTransparencyStatusDidChangeNotification" in tweak
assert "UIAccessibilityDarkerSystemColorsStatusDidChangeNotification" in tweak

# Shared rims retain their default palette and geometry; only opted-in instances change.
assert "GFLockRimShadeColors(NO)" in rim
assert "lightSurface ? 2.5 : 1.0" in rim
assert "self.gfCircular ? 0.8 : (self.gfSubdued ? 1.4 : 1.6)" in rim
assert "kCACornerCurveContinuous" in rim
print("Notification foreground-aware guard and restoration static checks: PASS")
