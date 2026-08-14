# GlassFolders 0.7.3 Beta 2.4 — Background Hosted Glass

Fixes the App Library card offset shown on-device.

## Geometry correction

Beta 2.x inserted the custom glass into `SBHLibraryPodFolderView` and copied
geometry from an inner background object into the pod's coordinate system.

The real App Library hierarchy has additional internal layout offsets, so the
glass could be visibly shifted from the category card.

Beta 2.4 removes that cross-view geometry entirely.

The glass is now a child of the real visual surface:

`SBHLibraryCategoryPodBackgroundView`

with:

`glass.frame = backgroundView.bounds`

No frame conversion is used.

`SBHLibraryPodFolderView` remains only a lifecycle/discovery bridge for
lazily-created category backgrounds.

## Stock material

The system background host remains alive, preserving Apple's frame, radius,
reuse and animation lifecycle.

While enabled:

- host background colors are cleared;
- stock material descendants are hidden;
- one `GFPanelGlassView` fills the host bounds;
- icons, labels, hit-testing and expansion remain untouched.

## Existing safeguards

Retained:

- closed Home Screen folder glass;
- opened folder glass;
- PreferenceLoader nested icon packaging and final-deb verification;
- RootHide arm64e;
- SpringBoard-only injection;
- no broad App Library controller/icon-list/search hooks;
- no timer, polling, DisplayLink, gyro or continuous Metal rendering.
