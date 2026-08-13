# GlassFolders 0.5.2 / Test5.2 — Edge Glass

## Why this version

Test5 was too visually flat compared with the supplied iOS 27 reference.
Test5.1 increased the glass strength but used a full-area diagonal highlight.

Test5.2 changes the highlight model:

- very weak full border
- stronger top/upper-left catch-light
- no full-area diagonal highlight
- no animated lighting
- no gyroscope response

The design follows the principle that the material should remain translucent
and let the wallpaper color pass through while using subtle edge light to make
the glass boundary readable.

## Liquid Glass

Closed folder:
- `UIBlurEffectStyleSystemUltraThinMaterialLight`
- very light white tint
- 1 physical-pixel weak border
- one tiny static gradient located only on the top edge
- top-left is brightest, fades toward the right

Opened folder:
- no new blur view
- reuses Apple's existing `SBFloatyFolderView` material
- larger surface is slightly "thicker" than the small closed-folder plate
- Apple's own open/close animation remains intact

## Performance

No:
- daemon
- timer
- DisplayLink
- motion sensor
- continuously animated gradient
- custom full-screen blur
- shadow rendering loop

At Clear 0%, no `UIVisualEffectView` is created for a closed folder.

## Suggested test

Liquid Glass:
- 40%
- 45%
- 50%
- 55%

Compare 45–50% against the iOS 27 reference.

If Edge Glass still looks too flat, the next A/B experiment should replace only
the tiny top-edge highlight with a static diagonal specular band. Do not expose
both as permanent user-facing options unless testing proves both are useful.
