# GlassFolders 0.5.7 / Test5.7 — Continuous Edge Glass

## Fix

Test5.6 used two separate static gradient strips:
- one along the top edge
- one along the left edge

Because both strips were inset and clipped independently, the rounded
top-left corner could look like the highlight was missing.

Test5.7 replaces both strips with:

- one `CAGradientLayer`
- one `CAShapeLayer` rounded-rectangle stroke mask

The highlight is now a single continuous perimeter path.

## Visual behavior

- strongest at the upper-left corner
- still visible across the top and left
- fades toward the lower-right
- no diagonal white stripe across the folder interior
- no seam at the rounded corner

The highlight region is about 2.8pt wide, intentionally thicker than a
1-pixel border but still soft.

## Performance

This is actually simpler than Test5.6:
- one gradient layer
- one static shape mask
- no animation
- no DisplayLink
- no timer
- no gyroscope

Backdrop Glass, 5% detents, crisp haptics, and `应用并注销` remain unchanged.
