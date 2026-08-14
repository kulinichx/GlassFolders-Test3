# GlassFolders 0.7.2 Beta 3 — Connected Edge Rail

Beta 3 keeps the Beta 2 material calibration and changes only the opened-panel
edge-lighting distribution.

## Why

The new reference has a useful property: the glass is not defined by a uniform
white outline. Instead, the top and bottom edges are bright and clean, while
the highlight continues through the top-left and bottom-right rounded corners.

That continuity makes the surface read as one optical object.

## Edge model

The opened panel now combines five terms:

1. continuous low-level perimeter filament;
2. stronger top horizontal highlight rail;
3. slightly weaker bottom horizontal highlight rail;
4. top-left / bottom-right corner bridge;
5. existing directional key specular + far-side secondary rim.

The corner bridge is derived from the rounded-rect SDF surface normal. It is
not a `CAShapeLayer` stroke and does not draw an explicit rounded rectangle.

A small wider core sits under the bright filament so the result should remain
glass-like rather than neon.

## Strength

The Beta 2 strength calibration is unchanged:

- material: `pow(s, 1.10)`
- specular: `pow(s, 0.80)`
- tint: `pow(s, 1.35)`
- recommended daily point: 55%

This iteration intentionally leaves blur/tint unchanged so the effect of the
new edge distribution can be evaluated independently.

## Stability boundary

Unchanged:

- `SBFolderIconImageView` for the closed folder;
- `SBFolderBackgroundView` for the opened visual panel;
- no parent folder container hook;
- no page-background factory hook;
- no transition-alpha hook;
- no outside wallpaper-background hook.

No daemon, timer, DisplayLink, gyroscope, or continuous Metal rendering.
