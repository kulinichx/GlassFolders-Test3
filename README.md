# GlassFolders 0.7.0 Beta 3 — Balanced Optical Edge

Beta 3 keeps the SDF lighting architecture and focuses on the two device
observations from Beta 2:

1. the right/bottom edge from an earlier build looked good and should not vanish
2. the opened panel showed tiny white artifacts around its four corners

## Closed folder

### Directional upper-left light

Still uses:
- narrow specular filament
- supporting core
- wide soft shoulder

This creates the stronger upper-left reflection.

### Faint full-perimeter edge definition

A new very-low-gain `baseEdge` is derived from the narrow SDF filament profile
but does not depend on the light direction.

Its job is only to preserve the subtle right/bottom glass edge seen in the
supplied RootHide and Alook references.

It is intentionally much weaker than the upper-left directional highlight.

## Opened folder

### Material

Adjusted toward the supplied Apple opened-folder reference:

- slightly less blur
- slightly brighter backdrop
- a little more neutral white frost
- wallpaper color still passes through

### Corner artifact fix

Two protections are now used:

1. SDF texture boundary uses sub-pixel coverage instead of a binary cutoff
2. `GFOpenedFolderGlassView` gets a dedicated rounded `CAShapeLayer` mask

The mask is inset by less than half a point and uses a slightly safer radius,
so backdrop filters and lighting texture cannot leak into the four extreme
corners.

### Opened optical edge

The opened panel keeps:
- wider soft shoulder
- softer core
- weaker/narrower filament
- extremely faint full-perimeter definition

It should read as a frosted glass panel, not a white outlined card.

## Performance

Still no:
- daemon
- Timer
- DisplayLink
- gyroscope
- per-frame Metal renderer
- animated gradient

Optical maps are generated on size/radius/5%-strength/open-state changes and
cached in `NSCache`.

## Opened panel safety

The RC3 host detection remains:

- glass attaches only to the actual rounded folder panel
- no full-screen custom fallback
- unresolved panel => keep stock SpringBoard background
