# GlassFolders 0.7.3 Beta 2 — App Library Pod Container

This build replaces the unsuccessful App Library Beta1.x approach.

## What the on-device result proved

The nested small folder-like element in App Library already received
GlassFolders through the normal `SBFolderIconImageView` path.

The large outer category cards did not.

The AppLibraryController public headers identify:

`SBHLibraryPodFolderView : SBFolderView`

as the App Library pod folder container.

Its tweak source separately uses
`SBHLibraryCategoryPodBackgroundView -_updateVisualStyle`
for the category background visual.

## Beta 2 architecture

For each `SBHLibraryPodFolderView`:

1. locate its exact `SBHLibraryCategoryPodBackgroundView` descendant;
2. use that descendant only for system frame + corner radius;
3. hide the whole stock background view;
4. insert one `GFPanelGlassView` at index 0 of the pod container;
5. keep icons, labels, touch handling, and folder expansion untouched.

The custom glass frame is converted from the real system background view into
pod coordinates. If that exact background is not present yet, Beta 2 does
nothing and waits for the next UIKit layout callback; it does not guess a card
frame.

The descendant is cached per pod, so the recursive search is not repeated after
the background is resolved.

## App Library hooks

Only these visual classes are used:

- `SBHLibraryPodFolderView`
- `SBHLibraryCategoryPodBackgroundView`

No App Library controller, pod folder controller, icon-list view, icon view,
search controller, or navigation hook is added.

## PreferenceLoader icon

The Settings entry now follows the common PreferenceLoader structure:

`/Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`

with its icon next to it:

`/Library/PreferenceLoader/Preferences/GlassFolders/GlassFoldersIcon.png`

and the `entry.icon` value is the absolute path above.

1x/2x/3x PNG variants are included.

## Existing behavior

Unchanged:

- closed Home Screen folder optical glass;
- opened folder `SBFolderBackgroundView` glass;
- percentage-driven edge calibration;
- dark/light adaptation;
- independent App Library switch;
- RootHide arm64e;
- SpringBoard-only tweak injection.

No daemon, timer, polling loop, DisplayLink, gyroscope, or continuous Metal
rendering.
