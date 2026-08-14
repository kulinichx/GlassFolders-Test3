# GlassFolders 0.5.11 — Opened Native Transparent Glass

## Target

This version combines the closed-folder calibration with the supplied Apple
opened-folder reference.

Desired opened-folder look:

- one large translucent glass panel
- wallpaper color clearly passes through
- app icons remain crisp
- rounded white rim is subtle and neutral
- no diagonal white stripe
- no white/gray frosted-card look
- surrounding desktop blur/dim remains Apple's stock effect

## Implementation

`SBFloatyFolderView` now receives one lightweight
`GFOpenedFolderGlassView` behind its content.

The custom opened glass uses:

- `CABackdropLayer` when available
- static saturation / brightness / Gaussian blur filters
- nearly zero white tint
- one faint complete white outline
- one neutral-white gradient rim

The large surface is intentionally a little "thicker" than the closed folder:

- slightly stronger blur
- slightly lower saturation boost
- still wallpaper-colored

## Animation

No open/close animation is rewritten.

The system continues calling `setBackgroundAlpha:`. GlassFolders maps that
same alpha directly to the custom glass view, so the panel follows Apple's
existing zoom/fade transition automatically.

Apple's original folder panel material is set to zero opacity only in
Liquid Glass mode.

The surrounding wallpaper blur/dim is not replaced or duplicated.

## Performance

No:
- daemon
- Timer
- DisplayLink
- gyroscope
- animated gradient
- custom full-screen blur
- custom transition animator

At runtime the opened effect adds only one static backdrop view while a folder
is open.

## Existing UX retained

- 5% magnetic detents
- crisp rigid haptic ticks
- magnetic settle on release
- 应用并注销
