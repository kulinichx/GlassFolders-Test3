# GlassFolders 0.7.4 Beta 1.7 — End-Gated Specular Rails

This build fixes the endpoint-ownership problem visible on-device in Beta 1.6.1.

## Observed problem

The shared rail masks correctly made:

- upper-left + top equal-brightness;
- bottom + lower-right equal-brightness.

However, the raw `topFacing` / `bottomFacing` normals also remain non-zero
inside the opposite rounded corners.

That caused:

- the top rail to continue visibly through the upper-right corner;
- the bottom rail to continue visibly through the lower-left corner.

The result looked too close to four illuminated corners.

## Beta 1.7 geometry

Normal-based rail shape is now combined with positional endpoint gates.

### Primary rail

The primary rail still consists of:

`upper-left corner -> full top edge`

It stays at 100% through the upper-left corner and straight top.

Only after entering the upper-right radius does `primaryEndpointGate`
smoothly attenuate it, reaching 12% at the far end of that corner.

### Secondary rail

The secondary rail still consists of:

`full bottom edge -> lower-right corner`

The lower-left radius is attenuated in the mirror direction. The bottom
straight and lower-right corner remain at 100%.

### Why position is required

A surface normal cannot distinguish a straight horizontal segment from the
adjoining rounded radius because both can point upward/downward.

The gate therefore uses the pixel's x position relative to the actual corner
radius. No extra view/layer/runtime work is added.

## Non-owned corners

Upper-right and lower-left retain only subtle transition structure.

Their explicit transition gain and dark-shoulder contribution were both reduced.

## Closed / opened

Both cached optical maps use the same endpoint topology.

No hooks were added or changed.

## Safety / performance

Unchanged:

- RootHide arm64e;
- SpringBoard-only injection;
- `SBFolderIconImageView`;
- `SBFolderBackgroundView`;
- no App Library code;
- no daemon;
- no timer;
- no DisplayLink;
- no gyro;
- cached CPU-generated SDF optical maps;
- rounded Settings icon;
- duplicate PreferenceLoader cleanup;
- `作者  kulinich`.
