# GlassFolders 0.7.3 Beta 2.3 — Legacy PreferenceLoader Cleanup

The SpringBoard runtime code is unchanged from Beta 2.2.

## What the Beta 2.2 log proved

The final dylib already contained all intended visual symbols:

- `SBFolderIconImageView`
- `SBFolderBackgroundView`
- `SBHLibraryCategoryPodBackgroundView`
- `SBHLibraryPodFolderView`
- `_updateVisualStyle`

The final deb also contained the nested PreferenceLoader plist and its 1x/2x/3x
PNG icons.

The verifier failed only because it incorrectly required an additional copy of
those PNGs inside `GlassFoldersPrefs.bundle`.

## Real Settings-entry conflict

The final deb also contained an obsolete top-level file:

`/Library/PreferenceLoader/Preferences/GlassFolders.plist`

at the same time as the corrected nested entry:

`/Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`

That stale file is not in the current source tree; it can remain in a long-lived
GitHub repository when newer ZIPs are overlaid without deleting old files.

Beta 2.3 explicitly removes the legacy top-level plist and old top-level icon
files before every GitHub build.

## Final package verification

The deb must contain:

- `GlassFolders/GlassFolders.plist`
- `GlassFolders/GlassFoldersIcon.png`
- `GlassFolders/GlassFoldersIcon@2x.png`
- `GlassFolders/GlassFoldersIcon@3x.png`

The deb must NOT contain:

- `Preferences/GlassFolders.plist`

The redundant PreferenceBundle icon requirement has been removed.

## Runtime

Unchanged from Beta 2.2:

- closed Home Screen folder glass;
- opened `SBFolderBackgroundView` glass;
- App Library Pod-container glass;
- RootHide arm64e;
- SpringBoard-only injection.
