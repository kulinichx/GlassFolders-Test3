# GlassFolders 0.7.3 Beta 1.4 — Exact App Library Hook

Two focused corrections.

## 1. App Library large category cards

The small nested folder-like element inside an App Library category was already
receiving the normal `SBFolderIconImageView` glass. That did not prove the
App-Library-specific hook was working.

Beta 1.4 removes the runtime class scan and targets the dedicated category
background class directly:

`SBHLibraryCategoryPodBackgroundView`

Startup sequence:

1. explicitly load SpringBoardHome;
2. resolve `SBHLibraryCategoryPodBackgroundView`;
3. allow one leading-underscore alias only;
4. initialize the Logos group against that exact class.

No `SBHLibraryPodFolderView`, App Library controller, icon-list, search
controller, or navigation hook is added.

The category-background object is visual-only, so its stock material children
can be suppressed without touching category icons.

## 2. Settings icon

The PreferenceLoader plist previously stored `icon` at the plist root.

PreferenceLoader builds the Settings row from the `entry` dictionary, therefore
the root-level key was ignored.

Beta 1.4 moves:

`icon = GlassFoldersIcon.png`

inside `entry`.

The image is also present in `GlassFoldersPrefs.bundle` with 1x/2x/3x variants,
so no hard-coded RootHide jbroot filesystem path is needed.

## Existing behavior

Unchanged:

- closed Home Screen folder glass;
- opened folder glass;
- edge percentage calibration;
- App Library switch;
- dark/light adaptation;
- static icon artwork;
- RootHide arm64e;
- SpringBoard-only injection.

No daemon, timer, polling loop, DisplayLink, gyroscope, or continuous Metal
renderer.
