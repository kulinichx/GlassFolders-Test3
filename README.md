# GlassFolders 0.7.2 Beta 4 — Apple Edge Intensity

Beta 4 is an edge-lighting calibration based on the 75% on-device result and
the brighter system reference.

## Problem fixed

Beta 3 had two issues:

1. left/right straight edges were too prominent;
2. 55% -> 75% -> 100% did not change edge brightness enough.

The cause was that several optical gains contained large constant terms. The
slider therefore changed the material more than the visible edge reflection.

## New edge-strength response

Beta 4 introduces a dedicated edge curve:

`edge = 0.12*s + 0.88*pow(s, 1.80)`

Approximate response:

- 25% -> 0.10
- 50% -> 0.29
- 55% -> 0.35
- 75% -> 0.62
- 100% -> 1.00

High percentages now have substantially more authority over the specular edge.

## Light distribution

Brightness budget is intentionally non-uniform:

- top rail: strong;
- bottom rail: strong but slightly below top;
- top-left rounded corner: strongest connected highlight;
- bottom-right rounded corner: strong connected highlight;
- left/right straight sides: reduced by roughly one third to one half;
- far-side secondary rim: attenuated on vertical straight sides.

A low-level perimeter filament remains so the glass never looks broken.

## Material

Blur, saturation, tint, dark/light adaptation, and the runtime architecture are
unchanged from Beta 3. This isolates the edge-lighting change.

## Stability boundary

Still unchanged:

- closed folder: `SBFolderIconImageView`;
- opened panel: `SBFolderBackgroundView`;
- no parent folder container hook;
- no page-background factory hook;
- no transition-alpha hook;
- no outside wallpaper-background hook.

No daemon, timer, DisplayLink, gyroscope, or continuous Metal rendering.
