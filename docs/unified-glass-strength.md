# Unified Glass Strength And Reference Slider

2026-11-13. Supersedes the independent notification/Dock blur controls after
device feedback. The active Clear/Liquid Glass strength is now the single
authority for all enabled glass surfaces. Per-surface switches remain separate.

## Controls And Compatibility

Only `ClearStrength` and `LiquidGlassStrength` remain as percentage specifiers;
the selected style shows one of them. Their existing values and legacy
`GlassStrength` fallback are retained. `NotificationBlur` and `DockBlur` are no
longer read or exposed, but stored preferences are not deleted.

The active `GFGlassStrength` drives folders, App Library, Dock, Home/app banners,
lock notifications, music, Live Activities and quick-action buttons. At 50%,
existing per-scene midpoint recipes apply. Zero omits our Gaussian; 100% doubles
the midpoint radius. Different-sized surfaces keep appropriate baseline radii:
Dock 5/3 (normal/light), notifications 4/3 (dark/light), generic cards/app banners
8 and quick actions 3. Folder strength keeps its existing style-specific response
rather than being silently recalibrated. Body palettes and edge geometry stay.

Cached material inputs now include the shared amount for library/Dock. Retained
music, activity and button backgrounds also receive the cached blur refresh.
Fallback effect alpha scales with the same amount; it is not a Gaussian-radius
equivalent. There is no new polling, screenshot capture or render loop in the
shipping tweak.

## Slider Correction

The previous frame adjustment passed translation-only mock tests but failed on
the device: the original system control still drew through the percentage.
`GFPercentSliderCell` now derives from `PSTableCell` and owns its system UISlider
and label. It is registered as a custom static cell, not a PSSliderTableCell.
Auto Layout reserves 52pt for the left percentage, a 12pt gap and an 18pt trailing
margin, matching the supplied reference. Continuous writes, 5% release detents,
rigid haptics, key reuse, legacy reads and live notifications are explicit.

The test-only UIKit application compiles the actual slider implementation with
Preferences stubs, then checks real UISlider track/thumb rectangles, repeated
layout, reuse, continuous writes and release detents on several row widths.
It exports light/dark screenshots and records the simulator runtime. This tests
UIKit, not the device's actual Preferences framework or iOS 16 compositor.

## Remaining Device Report

The reported dark overlap appearing after a swipe stops is not confirmed fixed.
The user was asked whether it is notification stacking or the desktop Dock
region; a Settings screenshot cannot establish that location or trigger. No
additional native shadow suppression or guessed private hook was added for this
unresolved report. Prior semantic notification-stack classification remains.

No device installation or on-device performance/energy measurement is performed.
