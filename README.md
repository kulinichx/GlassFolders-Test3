# GlassFolders 0.5.12 — Frosted Open Glass

Calibrated against the supplied Apple opened-folder reference.

## Closed folder

The Backdrop Glass color remains unchanged.

The hard outline has been removed:
- no base white stroke
- only one wider, much lower-opacity neutral-white rim
- edge reads as a soft transition, not a frame

## Opened folder

Target: "slightly frosted but still transparent".

Compared with 0.5.11:
- stronger blur
- lower saturation boost
- tiny additional neutral-white tint
- no hard base outline
- wider but much dimmer soft rim

The wallpaper color is still visible through the large panel, but details are
more softly diffused than in the closed folder.

## Mapping

One user-facing strength slider still controls both states.

Closed folder:
- clearer/thinner material

Opened folder:
- automatically one material-weight step thicker

No separate "opened folder strength" setting is added.

## Performance unchanged

No:
- daemon
- Timer
- DisplayLink
- gyroscope
- animated gradient
- custom full-screen blur
- custom transition animator

The opened panel still follows SpringBoard's own background-alpha animation.

## UX unchanged

- 5% magnetic detents
- crisp rigid haptic ticks
- magnetic settle on release
- 应用并注销
