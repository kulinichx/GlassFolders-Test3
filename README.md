# GlassFolders 0.7.0 Beta 2 — Crisp Specular

Beta 2 keeps the SDF optical-lighting architecture from Beta 1, but corrects
the "everything looks blurry" problem observed on-device.

## Reference interpretation

The supplied glass-style UI and third-party icon references share the same
edge structure:

1. a thin, readable white specular filament
2. a slightly wider supporting reflection/core
3. a broad, low-contrast soft shoulder
4. a weak lower-right dark falloff

The important point is that the crisp highlight and the soft transition coexist.
A single blurred stroke cannot reproduce this reliably.

## Beta 2 changes

### Backdrop silhouette

`gaussianBlur.inputHardEdges` is restored to `YES`.

The folder shape itself should stay crisp. Softness now comes from the optical
lighting profile INSIDE the edge rather than from letting backdrop blur bleed
across the clipping boundary.

### Closed-folder blur

Closed Liquid Glass blur is reduced.

Wallpaper/detail should remain more visible, avoiding the flat "purple fuzzy
card" appearance.

### Higher-resolution closed lighting

Closed-folder SDF maps now render up to the device's 3x scale.

This is important for a sub-point specular filament on Retina displays.

### Three-zone optical edge

Beta 1:
- core
- shoulder

Beta 2:
- filament
- core
- shoulder

The filament is narrow and directional.
The shoulder remains wide and low-contrast.

### No full white border

The filament intensity is multiplied by a stronger light-facing term, so it
appears primarily on upper-left-facing edges and corners.

It is not a uniform white rounded-rectangle outline.

## Opened panel

The RC3 panel-host fix remains.

Opened glass still:
- attaches only to the real rounded folder panel
- never falls back to full-screen custom glass
- keeps a more frosted material than closed folders
- uses the same three-zone optical law at lower contrast

## Performance

Still no:
- daemon
- Timer
- DisplayLink
- gyroscope
- per-frame Metal render loop
- animated gradient

Lighting maps are generated only when size/radius/5% strength/open-state changes
and are cached in NSCache.
