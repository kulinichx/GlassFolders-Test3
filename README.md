# GlassFolders 0.7.0 Beta 4 — iOS 27 Open Panel Correction

Beta 4 addresses two specific device observations.

## 1. Closed folder: missing right/bottom edge

Beta 3's lower-right shadow was stronger than the neutral edge definition,
therefore the right/bottom glass edge visually disappeared.

Beta 4 separates two physical-looking components:

### Back transmitted rim
- very narrow
- strongest on lower-right-facing normals
- low intensity
- neutral white

### Inner dark shoulder
- wider than the bright rim
- much lower dark-core strength
- provides thickness behind the rim

The intended lower-right profile is now:

`thin bright edge -> faint darker inner shoulder -> normal glass`

This preserves the user's preferred earlier right/bottom effect while keeping
the stronger three-zone upper-left specular.

## 2. Opened folder: match the supplied iOS 27 reference

The desired opened state is NOT a dark gray card.

Beta 4 opened material is:
- lower blur
- more wallpaper saturation/color retention
- noticeably brighter
- slightly stronger neutral white frost
- still transparent

The goal is a colored, lightly frosted glass panel.

## Four-corner artifact fix

Beta 3 intentionally inset the custom rounded mask by 0.42pt.

That could expose the stock SpringBoard folder material behind the custom panel
at the four corners.

Beta 4:

- removes the mask inset
- uses exactly `host.bounds`
- uses exactly the resolved host corner radius
- makes the real host clip its children to that same radius
- clears the host background
- suppresses only large background/material/backdrop/effect subviews inside the
  resolved panel host

Icons/content are not targeted by the stock-material suppression helper.

## Safety

The RC3 panel-host policy is retained:

- custom glass is only attached to a resolved rounded folder panel
- unresolved host => keep stock SpringBoard panel
- no full-screen custom fallback

## Performance

No:
- daemon
- Timer
- DisplayLink
- gyroscope
- per-frame Metal rendering
- animated gradient

SDF optical maps remain generated on demand and cached.
