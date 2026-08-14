# GlassFolders 0.7.0 Beta 5 — Alook Rim + First-Frame Open Glass

Beta 5 is based directly on the working Beta 4 RootHide project and makes two
targeted architectural changes. It deliberately does **not** change the
settings UI, 5% detents, haptics, package scheme, or SpringBoard-only injection.

## 1. Closed folder: Alook-style optical edge balance

Beta 4 still lost the right and bottom edge on-device because those regions were
derived from the light-opposite term and then partially cancelled by the darker
inner shoulder.

Beta 5 separates the optical roles:

### Upper-left / top
- crisp neutral-white filament
- supporting core
- wide soft shoulder
- fixed upper-left light direction

### Right / bottom
- independent narrow secondary rim
- neutral white, much weaker than the upper-left specular
- gentle inner dark shoulder starts *after* the rim
- lower-right corner remains continuous without becoming a painted frame

The intended profile is:

`upper-left strong reflection -> transparent body -> thin right/bottom rim -> faint inner dark shoulder`

The secondary rim is not a full white border and is not derived solely from
N·L, so it remains visible on the unlit sides.

## 2. Opened folder: remove the black-to-light first-frame flash

Beta 4 waited until `layoutSubviews` / `setBackgroundAlpha:` to locate and
overlay a panel. That allowed SpringBoard's stock dark folder material to be
visible for the initial part of the transition.

Beta 5 hooks:

`-[SBFloatyFolderView _newPageBackgroundView]`

SpringBoard's own page-background object is still returned unchanged. Before it
is returned to the caller, Beta 5:

- registers the real page-background object
- installs `GFOpenedFolderGlassView` inside it
- resolves the historical `backgroundView` dynamically when present
- suppresses only the stock full-size blur/tint/material content
- applies the real folder corner radius
- leaves Apple's page/container transition in control

`setBackgroundAlpha:` now calls `%orig(alpha)` instead of `%orig(0.0)`.
Because our glass is a child of the true page background, Apple's native
transition animates it automatically.

After SpringBoard updates alpha/effect/layout, Beta 5 re-suppresses the stock
material synchronously so it cannot reappear.

## Opened visual target

The visual calibration remains the existing light, color-retaining frosted
panel:

- independent rounded panel
- wallpaper color remains visible
- light frosting rather than dark gray material
- app icons/content remain separate from the background
- surrounding SpringBoard blur/dim remains native

This beta primarily fixes *timing and ownership* of the panel instead of
randomly changing blur/tint parameters again.

## Performance

No:
- daemon
- Timer
- DisplayLink
- gyroscope
- per-frame Metal renderer
- custom animation loop

The closed-folder optical map is still generated only for a new
size/radius/5%-strength combination and cached.
