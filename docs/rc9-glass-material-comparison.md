# RC9 Glass Material Comparison

The later user-requested [adjustable notification blur](notification-blur-control.md)
uses this study's separation of responsibilities. This file records the prior
read-only study, not the current implementation status.

Read-only source study, 2026-11-13. Reference checkout:
`G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next`, branch
`rc9-ios16-next`. No RC9 files or rendering code were changed. The earlier
low-blur candidate remains local and unbuilt; its push/build is on hold.

## Active Implementation

The active material is `Application/Dopamine/UI/DOCustomGlassView.m`:

- `DOCustomLiquidGlassView`, starting at line 106, uses `CABackdropLayer`.
- `reloadMaterial`, line 220, separates glass blur, body transmission and
  perimeter highlight. Wallpaper blur belongs to a different background path.
- Lines 264-311 apply saturation, brightness and Gaussian blur. Lines 337-362
  set a separate neutral body. Lines 371-409 configure directional highlight
  layers; these layers do not displace background pixels.
- Nested action pills in `DOMainViewController.m:428` set
  `materialBackdropScale = 0` and `suppressBackdrop = YES`. Their outer platter
  owns the backdrop pass, avoiding a second full-strength local blur.
- The supplied checkout does not use the retired Metal refraction overlay in
  its active glass view. This is a material reference, not a verified live
  refraction bridge for SpringBoard.

`DOCustomGlassView.h:141` defines the Main Glass role. With the source defaults
of glass blur 0.85 and transparency 0.70, and that role's backdrop scale 0.92:

| Source recipe | Computed filter radius | Computed neutral body alpha |
| --- | --- | --- |
| Light Glass, light interface, base tint 0.05 | 13.790 | 0.07484 white |
| Dark Glass, base tint 0.05 | 15.431 | 0.12285 black |

These are arithmetic results from the source, not measured physical blur sizes,
not the user's saved settings, and not a visual equivalence across applications.
In particular RC9's default radius is not lower than our former notification
radius 8. Copying its numbers would not demonstrate less frosted notifications.

## White And Black Backgrounds

RC9 controls its own background. `DONavigationController.m:286` computes a
brightness-dependent black scrim, capped at 0.35. Lines 949-994 sample five
wallpaper bands when source/viewport changes and apply that scrim. Meanwhile
`DOCustomGlassView.h:59` keeps the foreground light. The app's readability must
be considered with this background treatment, not only its glass layers.

Our notification tweak must not dim the entire system wallpaper or adopt fixed
white foreground text to reproduce that app composition. Background luminance,
not the system light/dark interface setting or RC9's Light/Dark Glass selector,
must continue to choose notification foreground polarity.

Gaussian blur alone does not separate a panel from an ideal uniform background:
white stays white and black stays black away from boundaries. Refraction of an
ideal uniform source likewise has no visible texture to bend. Do not compensate
by making either blur or displacement excessively strong.

Current `GFNotificationPalette.h` already selects dark foreground for light
wallpapers and light foreground for dark wallpapers, with hysteresis. On pure
white its neutral body is white 0.78 at alpha 0.18. Ideal source-over arithmetic
gives channel 0.9604 over white, creating slight absorption rather than a white
fill. On pure black the black body at alpha 0.035 remains black, so existing rim
contrast carries the panel boundary. These calculations are not device renders
or measured text contrast; native composition and shadows still require testing.

## Recommended Scope

1. Keep the existing rim geometry, highlights and light-background contour.
2. Borrow RC9's separation of responsibilities, not its complete filter values,
   global scrim, fixed light text, authorization code or app wallpaper renderer.
3. Check for repeated material sampling before choosing a lower blur radius.
   Our existing capture groups and disabled in-place filtering must remain.
4. Preserve current body/foreground adaptation during the first comparison.
   Any later neutral-body adjustment should be a separate, explicit comparison,
   not silently bundled with blur or edge changes.
5. Keep the current overscanned sampling and clipping strategy. RC9 sets
   `inputHardEdges`; our backdrop deliberately omits that flag to avoid clamped
   corner sampling. Do not transplant it without a specific device regression.

Acceptance must cover pure white, pure black, near-white, near-black, saturated
wallpaper, fine texture and bright/dark mixed wallpaper. For each, compare front
and rear notifications, expanded/collapsed stacks, Home Screen banners and
transition into app banners. Check title/body/time/icon legibility as well as
material separation. Preserve native content if wallpaper adaptation is unknown;
do not infer app pixels from the Home Screen wallpaper.

## Verification

RC9's existing `node --test tests/glass-ui-contracts.test.cjs` completed with
46 passing, 0 failing and 3 platform-specific tests skipped on Windows.
This supports source contracts only. No iOS compilation, screenshot comparison,
GPU run, private compositor ABI validation or phone installation was performed.
