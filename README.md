# GlassFolders 0.7.4 Beta 1.6 — Continuous Specular Rails

This calibration implements the visual correction from the Apple reference:

- upper-left rounded corner and the full top edge are ONE continuous
  equal-brightness highlight;
- the full bottom edge and lower-right rounded corner are ONE continuous
  equal-brightness secondary highlight;
- straight left/right side middles are substantially quieter.

## Why this is different from Beta 1.5

Beta 1.5 still treated corner energy and straight-edge energy as separate
components. Even with similar coefficients, the rounded corner could read as a
bright spot attached to a different top line.

Beta 1.6 constructs a shared geometric mask for each rail.

### Primary rail

`primaryRailMask`

is the union of:

- the straight top-facing normal;
- the saturated upper-left rounded-corner bridge.

The same shoulder/core/filament gains are multiplied by the whole mask, so the
highlight turns through the upper-left radius without changing luminance.

### Secondary rail

`secondaryRailMask`

does the same for:

- the straight bottom edge;
- the lower-right rounded corner.

The secondary rail is intentionally slightly softer than the primary rail, but
its bottom segment and lower-right corner are equal to each other.

### Other edges

Upper-right and lower-left retain only low transition structure.

The straight left/right side middles use `sideMiddleMask` and a very small gain,
so they do not read as a uniform white outline.

## Closed and opened folders

Both optical maps use the same topology.

The opened folder remains broader/softer because its glass surface is larger,
but the highlight organization is identical.

## Safety / performance

Unchanged:

- RootHide arm64e;
- SpringBoard-only main injection;
- only `SBFolderIconImageView` and `SBFolderBackgroundView`;
- cached CPU-generated SDF optical textures;
- no timer;
- no DisplayLink;
- no gyro;
- no daemon;
- no App Library code;
- rounded Settings icon retained;
- duplicate PreferenceLoader cleanup retained;
- `作者  kulinich` retained.
