# LowWakeup2 WhiteBG Test 3

Date: 2026-11-08. Baseline remains `32b1022`, corresponding to the recorded
`1.3.1~lowwakeup2` package. Candidate version:
`1.3.1~lowwakeup2+whitebg3`, RootHide arm64e; preference build `1.3.1.4`.

## Device Feedback And Reference

The user installed WhiteBG2 and reported readable main text, an almost invisible
panel on white wallpaper, and a brief material/blur flash during stack expansion.
The supplied screenshot also has white timestamps. WhiteBG2 did not pass device
visual acceptance.

The newer Apple reference has a pale gray exterior, a brighter card interior,
dark main text, gray dates and recognizable wallpaper details inside the panel.
It establishes a visual target, not the OS's private implementation. A pure
white exterior has no headroom for the same white-on-gray luminance separation.
Do not globally dim the user's wallpaper to manufacture a matching screenshot.

Read on 2026-11-08:

- Apple HIG Materials:
  https://developer.apple.com/design/human-interface-guidelines/materials
  (official JSON document also read). The regular variant blurs and adjusts
  luminosity to preserve legibility. Clear and its optional 35% dimming guidance
  are a different use case, not a notification recipe.
- Apple WWDC25, Meet Liquid Glass, session 219:
  https://developer.apple.com/videos/play/wwdc2025/219/
  The transcript describes coordinated tint, foreground, edge/light and shadows.
  Shadow opacity decreases over a solid light background. This does not establish
  an iOS 27 notification shader or justify large fixed drop shadows.
- Runtime interface reference, MTACS/iOS-17-Runtime-Headers:
  `NCNotificationSeamlessContentView`, `PLPlatterHeaderContentView`,
  `PLTitledPlatterView`, `BSUIDefaultDateLabel`. Both notification date hosts expose
  `_updateTextAttributesForDateLabel`. The date label is a UILabel subclass.
  Runtime signatures are guarded on device; these dumps do not prove iOS 16 ABI.

The earlier Mango audit established separate optical controls, but no proven
notification adaptation call chain. This version does not relabel that evidence
as a port of Mango or Apple's private Liquid Glass.

## Changes

- The production stack setter only updates rim/veil decoration. It no longer
  invokes the superclass material refresh, which assigns a folder recipe before
  assigning the notification recipe and recreates filter/effect objects.
  This removes a concrete unnecessary refresh path; device evidence is still
  needed to establish whether it accounts for all reported flashes.
- Keep notification body tint constant across the stack threshold. Retain
  existing materials through temporary empty background bounds while hidden,
  instead of exposing native blur and recreating the replacement on next layout.
  Disable, detached, changed-layout and accessibility fallback still restore.
- Skip redundant geometry assignments while retaining native animation contexts.
- For identified light notifications use 3 pt blur instead of 8 pt; dark cards
  and other scenes retain their existing recipe. Wallpaper mode changes can
  reconfigure the backdrop; stack changes cannot.
- Use the existing 18% neutral body layer. Where there is luminosity headroom,
  retain white lift. Above linear luminance .85, smoothly lower the layer's
  white value to .78 at pure white. A uniform white input becomes .9604 before
  edge composition, while retaining 82% source contribution in this layer.
  This is a project calibration, not an Apple numerical recipe.
- Add an opt-in one-point absorbing contour, feathered at display-pixel
  intervals, following the same continuous curve as the panel. Keep directional
  white reflection and the existing shallow inner shade. Non-notification
  scenes never enable the new contour.
- Reapply managed foreground after both date hosts' independent date-attribute
  update, as well as the existing layout/date callbacks. This addresses a missed
  lifecycle path; it does not prove all white dates on the user's runtime are
  caused by that path.

No scheduler, activation, preference controller or global label hook changes.

## Validation

- Five source integration/provenance checks and 6,006 actual palette contrast
  cases pass locally, including a non-white surface on pure white input.
- macOS production foreground harness covers date restyling and label replacement,
  preservation of fonts/attributed content, native updates and restoration.
- macOS production stack-subclass harness tests 400 alternating transitions
  retain filter/effect identity; explicit refresh still works.
- macOS QuartzCore render uses the actual production rim and palette, checks
  pixels on white, and saves a paired before/after image. This isolates the edge;
  it does not emulate SpringBoard, blur sampling or animation.
- The workflow compiles the actual iOS tweak and preferences and validates DEB
  identity, architecture, resources and single preference entry.

Build and artifact verification: PASS, run `42473220244`, source
`924b603f5cbaf176cc69ffa4298702c2613ecdaf`. RootHide job: 1m59s.
The production foreground, stack and edge-render harnesses all passed, followed
by actual iOS tweak/preferences compilation and package validation. The edge
render measured 211/255 at its darkest sampled top-edge pixel and 245/255 in the
body on pure white. The paired PNG was downloaded and visually inspected;
new contours are visible and background marks remain visible. This is isolated
edge composition, not a device screenshot.

Package:
`G:\AITEST\GlassFolders 1.0\DEB\11-8\WhiteBG3\kulinich.glassfolders_1.3.1-lowwakeup2-whitebg3.deb`
(91,002 bytes).

SHA256:
`4ae4b214ef95a523fea57dab31c0f06573fdc3890a83cde7ffdbe4ea980aae98`.
The local hash matches the successful build log. Read-only local inspection
also confirmed package/version, preference build `1.3.1.4`, thin arm64e tweak
and preferences, new correction selectors, and exactly one Settings entry.
The only actual linker warnings were the existing obsolete
`-multiply_defined` option. Standard rootless was skipped.

Device visual and animation acceptance: pending.
