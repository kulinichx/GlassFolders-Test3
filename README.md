# GlassFolders 0.6.0 RC1 — Material Reset

This release intentionally stops tuning "borders" and instead models the
closed and opened folder as two material weights.

## Material model

### Closed folder — clear-like

Goal:
- highly translucent
- wallpaper remains visually dominant
- low blur
- modest saturation preservation
- almost no white tint
- no explicit edge stroke
- no rim mask
- no diagonal specular stripe

A broad radial white surface-light field near the upper-left provides a small
sense of depth without drawing a visible edge.

### Opened folder — regular-like / light frost

Goal:
- visibly more material weight than the small closed icon
- moderate blur for the larger surface
- restrained saturation
- small neutral-white tint
- wallpaper color still passes through
- no explicit border

The opened panel keeps using SpringBoard's own transition alpha and surrounding
desktop blur/dim.

## Why no drawn rim

The previous experimental releases treated the glass boundary as a rendered
stroke. On-device this repeatedly produced one of three artifacts:

- neon outline
- hard plastic-card edge
- disappearing/uneven highlight

RC1 removes the whole class of artifacts by deleting line-based edge effects.

## Performance

No:
- daemon
- Timer
- DisplayLink
- gyroscope
- animated highlight
- Metal shader
- custom full-screen blur
- custom transition animator

Static runtime cost:
- one CABackdropLayer-based plate per visible closed folder
- one broad static CAGradientLayer surface-light field
- one opened backdrop panel while a folder is open

## UX retained

- Clear / Liquid Glass
- one strength slider
- 5% magnetic detents
- rigid haptic tick across detents
- 应用并注销
