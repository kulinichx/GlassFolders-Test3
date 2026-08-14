# GlassFolders 0.5.13 — Soft Optical Rim

## Problem observed on device

0.5.12 still looked too "cut out":
- the glass boundary was geometrically hard
- the white rim was too dim to read as a highlight

## Changes

### Backdrop edge sampling

`gaussianBlur` now uses:

`inputHardEdges = NO`

for both closed and opened glass surfaces.

This allows the backdrop material to transition more naturally at the clipped
edge instead of behaving like a rigid card boundary.

### Closed folder rim

- width: 3.10pt
- much lower effective opacity than a visible stroke
- neutral white
- strongest at upper-left
- fades toward lower-right
- static Gaussian blur radius: 1.25

### Opened folder rim

- width: 3.60pt
- even softer because the large panel already has stronger frosted blur
- static Gaussian blur radius: 1.55

The rim is still static:
- no animation
- no timer
- no DisplayLink
- no motion sensor

## Opened panel

The 0.5.12 "frosted transparent" calibration remains:
- stronger blur than closed folders
- low saturation boost
- tiny neutral tint
- wallpaper color still visible

## UX unchanged

- 5% magnetic detents
- crisp rigid haptic ticks
- magnetic settle on release
- 应用并注销
