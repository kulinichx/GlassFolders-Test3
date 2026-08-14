# GlassFolders 0.7.0 Beta 1 — Optical Glass

This is a rendering-model change.

## Why

Earlier versions tried to create glass lighting with:

- drawn rims
- blurred strokes
- linear/radial CAGradientLayer overlays
- wide diagonal gradients

That repeatedly caused two failures:

1. highlight too sharp -> hard/artificial line
2. blur strong enough -> highlight disappears

## Optical model

### Backdrop material

`CABackdropLayer` remains responsible for:

- real wallpaper color
- blur
- saturation
- tiny neutral tint

### SDF lighting map

A small CPU-generated texture is derived from:

- rounded-rectangle signed distance
- numerical surface normal
- fixed upper-left light vector
- wide soft highlight shoulder
- narrower bright highlight core
- weak opposite lower-right dark falloff

No border is drawn.

No diagonal white stripe is drawn.

The diagonal glass feeling emerges because upper-left-facing normals receive
more white light while lower-right-facing normals receive a tiny dark falloff.

## Closed folder

- clearer backdrop material
- stronger optical highlight than opened panel
- wide shoulder + visible core
- no stroke / rim mask

## Opened folder

- RC3 real panel-host detection is retained
- independent rounded panel only
- lighter frosted-transparent backdrop
- wider, lower-contrast optical shoulder
- no full-screen custom blur

If the real panel host cannot be identified, GlassFolders keeps the stock
SpringBoard panel instead of falling back to full-screen glass.

## Performance

The optical texture is generated only for a new combination of:

- size
- corner radius
- 5% strength step
- closed/opened mode

Textures are cached in `NSCache`.

There is no:

- DisplayLink
- per-frame Metal rendering
- Timer
- gyroscope
- animated gradient
- daemon

## UX retained

- Clear / Liquid Glass
- 5% magnetic detents
- rigid haptic tick
- 应用并注销
