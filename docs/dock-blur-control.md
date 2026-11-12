# Adjustable Dock Blur Test

2026-11-13. Follow-up to the notification motion/slider fixes at source
`84efc56418fd8d9ca05574f7569d5d76fc63b7e2`. The user asked to update Dock glass
as well. This is an independent Dock blur control, not a folder-strength change
or genuine refraction implementation.

## Behavior

Settings adds **Dock Blur** (`DockBlur`, Chinese: Dock 模糊度), 0-100%, default
50%, using the corrected shared percentage slider and existing live reload.
It affects only enabled Dock **Glass Effect** mode. Dock's opt-in switch and
**Hide Background** mode are unchanged.

| Slider | Dark/unknown wallpaper recipe | Light wallpaper recipe |
| --- | --- | --- |
| 0% | No Gaussian | No Gaussian |
| 25% | 2.5 | 1.5 |
| 50% | 5 | 3 |
| 100% | 10 | 6 |

The previous Dock recipe used radius 10 throughout. The new midpoint reduces
frosting; 100% retains that radius on dark/unknown backgrounds. Light wallpaper
uses the existing cached Home wallpaper palette and a restrained neutral body
layer, independent of the system light/dark appearance. Invalid wallpaper input
uses the normal Dock recipe. Accessibility opt-outs for light adaptation remain.
Dock icons/content/labels remain native and are not traversed or recolored.

The existing horizontal Dock rim stays active on both white and black wallpaper;
its geometry and renderer source are unchanged. Library category/search cards
retain their original blur recipes, adaptive rims and style controls. Notification
blur remains independent. There is no new capture loop, timer or daemon.

## Native And Fallback Boundaries

The material cache includes the normalized Dock-only amount. Library instances
use a zero cache-key value, so moving the Dock slider cannot rebuild their
filters. Stable Dock layouts also retain filter identity.

Zero Gaussian is explicitly treated as a valid native backdrop, preventing an
accidental switch to a blurred UIVisualEffectView. On a platform without a usable
native backdrop, the existing fallback uses alpha 0-0.44 (0.22 at midpoint), not
a claimed equivalent Gaussian radius. Values are clamped and non-finite values
fall back to the midpoint.

## Verification

Source tests cover preference/localization wiring, independent keys, zero/native
handling, live reload and unchanged horizontal rim hash. The macOS production
renderer harness exercises white/black wallpaper, default/endpoints, clamping,
non-finite input, 400 stable layouts, missing Gaussian filter, absent backdrop,
fallback alpha and unaffected library recipes/filter identity. These are renderer
state tests with doubles, not an on-device compositor, appearance or power test.

The combined package must also include the preceding lock-screen semantic stack
classification and slider-coordinate fixes. Device comparison should cover
white/black/detailed wallpaper, 0/25/50/100%, page swipes, folder transitions,
Dock mode changes and disabling/restoring the native Dock background.
