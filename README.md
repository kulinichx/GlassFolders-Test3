# GlassFolders 0.7.2 Beta 5 — Closed Edge Intensity

Beta 5 fixes the percentage response of the Home Screen / closed folder.

## Root cause

Beta 4's aggressive percentage-driven edge curve was applied to the opened
panel, while the small closed folder still used the older `s^0.8` specular
mapping with large fixed gains.

That is why an on-device closed-folder screenshot at 100% looked very similar
to 75%.

## Beta 5 closed-folder response

The closed folder now uses the dedicated `GFEdgeResponse()` curve too.

Approximate edge drive:

- 25% -> ~0.10
- 50% -> ~0.29
- 55% -> ~0.35
- 75% -> ~0.62
- 100% -> 1.00

The optical peak itself is also percentage-dependent, so the high end cannot
be flattened by a fixed alpha clamp.

## Luminance distribution

The 100% screenshot also showed too much light on the straight left/right
sides. Beta 5 reallocates the brightness budget:

- top: strong;
- bottom: strong, slightly below top;
- top-left rounded corner: strongest;
- bottom-right rounded corner: strong;
- straight left/right sides: deliberately quieter;
- far-side secondary rim: favors bottom and bottom-right over straight right.

The corner bridge comes from the rounded-rect SDF surface normal; it is not a
painted `CAShapeLayer` stroke.

## Material and stability

Material blur/tint curves are unchanged. The opened-panel Beta 4 logic is also
retained.

Runtime boundary remains:

- closed folder: `SBFolderIconImageView`;
- opened panel: `SBFolderBackgroundView`;
- no parent folder-container/factory/transition-alpha hooks;
- SpringBoard-only injection;
- RootHide arm64e.

No daemon, timer, DisplayLink, gyroscope, or continuous Metal renderer.
