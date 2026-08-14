# GlassFolders 0.5.10 — Apple Transparent Rim

Calibrated against the supplied Apple "透明 / Transparent" appearance reference.

## Material

Backdrop rendering is unchanged from 0.5.9:

- light blur
- natural wallpaper saturation
- nearly zero white tint
- almost no brightness lift
- wallpaper remains the glass color source

## Edge model

The previous local path that ended part-way across the top has been removed.

0.5.10 uses two neutral-white static edge layers:

### 1. Base outline
- complete rounded rectangle
- ~0.60pt
- extremely low white alpha
- exists only to keep the glass silhouette coherent

### 2. Soft white rim
- complete rounded rectangle mask
- ~1.60pt
- upper-left is brightest
- smoothly fades toward lower-right
- no abrupt ending point
- no purple/blue tint in the highlight itself

The wallpaper may visually influence the perceived color underneath, but the
actual highlight colors are all neutral white.

## Performance

Still no:
- daemon
- Timer
- DisplayLink
- gyroscope
- animated highlight
- custom full-screen blur

The edge effect consists of:
- one CAShapeLayer base outline
- one CAGradientLayer
- one CAShapeLayer mask

## UX unchanged

- 5% magnetic detents
- crisp rigid haptic ticks
- magnetic settle on release
- 应用并注销
