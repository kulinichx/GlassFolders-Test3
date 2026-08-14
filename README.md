# GlassFolders 0.7.3 Beta 2.2 — Opened Group Restore

This fixes the Logos preprocessing failure shown by GitHub Actions:

`%init for an undefined %group GFOpenedPanelHooks`

## Root cause

During the Beta 2 App Library rewrite, the source replacement range started at
the old App Library helper section and extended too far. That accidentally
removed the already-stable `GFOpenedPanelHooks` group, while `%ctor` still
contained:

`%init(GFOpenedPanelHooks);`

Logos therefore stopped during preprocessing before Clang compilation.

## Beta 2.2 fix

The complete opened-folder group is restored byte-for-byte from the previously
working Beta 1.4.1 source:

- `SBFolderBackgroundView`
- `didAddSubview:`
- `didMoveToWindow`
- `layoutSubviews`
- `setBackgroundColor:`
- `traitCollectionDidChange:`

The Beta 2 App Library Pod-container code remains in place after that group.

## Build guard

The GitHub source sanity gate now explicitly requires both the `%group`
definition and `%init` call for:

- `GFIconHooks`
- `GFOpenedPanelHooks`
- `GFAppLibraryHooks`

This catches the exact class of source-structure error before Logos preprocessing.

## Settings icon

The Beta 2.1 packaging correction remains:

- PreferenceLoader nested plist + 1x/2x/3x PNG files;
- PreferenceBundle 1x/2x/3x/large PNG resources explicitly declared with
  `GlassFoldersPrefs_RESOURCE_FILES`;
- final `.deb` verification checks the actual packaged files.

## Runtime scope

- closed folder: `SBFolderIconImageView`;
- opened folder: `SBFolderBackgroundView`;
- App Library pod container: `SBHLibraryPodFolderView`;
- App Library card background reference:
  `SBHLibraryCategoryPodBackgroundView`;
- SpringBoard-only injection;
- RootHide arm64e.

No daemon, timer, polling loop, DisplayLink, gyroscope, broad App Library
controller hook, or continuous Metal renderer.
