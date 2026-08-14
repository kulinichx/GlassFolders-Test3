# GlassFolders 0.7.3 Beta 2.5 — Sibling Glass + Powercuff Icon Layout

## App Library

Device testing established two separate failures:

- putting glass on `SBHLibraryPodFolderView` can offset it;
- putting glass inside `SBHLibraryCategoryPodBackgroundView` can make it
  disappear with the system background host.

Beta 2.5 uses Apple's category background as geometry only.

The custom `GFPanelGlassView` is inserted immediately below it as a sibling in
the SAME superview and copies:

- bounds;
- center;
- transform;
- alpha;
- corner radius.

The stock category background is then hidden.

There is no cross-view coordinate conversion and the glass does not inherit the
stock background's hidden state.

`SBHLibraryPodFolderView` remains discovery/lifecycle only.

## Settings icon

PreferenceLoader recursively loads plist files under
`/Library/PreferenceLoader/Preferences`.

Powercuff uses one same-name directory containing:

- `Powercuff.plist`
- `Powercuff.png`
- `Powercuff@2x.png`
- `Powercuff@3x.png`

with `entry.icon` pointing at the base PNG.

GlassFolders now mirrors that structure exactly:

- `GlassFolders.plist`
- `GlassFolders.png`
- `GlassFolders@2x.png`
- `GlassFolders@3x.png`

The previous `GlassFoldersIcon*` basename is removed and CI rejects it if stale
copies reappear.

## Safety

Unchanged:

- closed folder: `SBFolderIconImageView`;
- opened folder: `SBFolderBackgroundView`;
- App Library visual classes only:
  `SBHLibraryPodFolderView` and
  `SBHLibraryCategoryPodBackgroundView`;
- RootHide arm64e;
- SpringBoard-only tweak injection;
- no App Library controller/icon-list/search hooks;
- no daemon, timer, polling, DisplayLink, gyro or continuous Metal renderer.
