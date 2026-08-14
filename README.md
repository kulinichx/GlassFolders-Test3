# GlassFolders 0.6.0 RC3 — Open Panel Host Fix

## Root cause fixed

Previous opened-folder builds placed the custom glass under
`SBFloatyFolderView`.

On the tested iOS 16.6 SpringBoard build, that object behaves as a large
container. When the old direct-child background lookup failed, the code used:

`targetFrame = self.bounds`

That made the custom backdrop effectively full-screen.

## RC3 host strategy

RC3 never uses the full `SBFloatyFolderView.bounds` as a fallback.

It recursively searches the opened-folder hierarchy for the real panel host,
scoring candidates by:

- folder/background/clip/material/backdrop class-name signals
- rounded-corner geometry
- panel-like area relative to the root container
- reasonable aspect ratio

Strong candidates such as a floaty-folder background clip/background view are
preferred.

Once identified:

- custom glass is inserted into that host
- `glass.frame = host.bounds`
- corner radius comes from that host
- app icons/page controls remain outside/above the glass
- surrounding wallpaper blur remains SpringBoard stock

## Safe fallback

If RC3 cannot identify the actual folder panel:

- custom opened glass is removed
- Apple's stock opened-folder background remains visible
- no custom full-screen blur is created

Wrong full-screen output is no longer an accepted fallback.

## Visual model retained

Closed:
- clear-like backdrop
- broad soft upper-left -> lower-right specular sheen
- no hard border

Opened:
- rounded independent panel
- lightly frosted transparent material
- restrained saturation
- tiny neutral tint
- no diagonal white stripe

## Performance / UX retained

- no daemon
- no Timer
- no DisplayLink
- no gyroscope
- no custom transition animator
- 5% detents
- rigid haptic ticks
- 应用并注销
