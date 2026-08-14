# GlassFolders 0.7.3 Beta 1.4.1 — Logos Init Fix

This is a build-only correction over Beta 1.4.

## What failed

Beta 1.4 declared the App Library hook group correctly, but initialized it with
a dynamic class-substitution form.

The build environment rejected that form at Logos preprocessing time with:

`%init for an undefined %group GFAppLibraryHooks`

## Beta 1.4.1

The runtime flow is now deliberately simple:

1. explicitly load SpringBoardHome;
2. check for `SBHLibraryCategoryPodBackgroundView`;
3. call `%init(GFAppLibraryHooks);`.

No runtime class scanning, no MSHookMessageEx path, and no class-token
substitution is used.

## Settings icon

The Beta 1.4 PreferenceLoader correction is retained: the `icon` key remains
inside the `entry` dictionary and the 1x/2x/3x assets remain packaged.

## Runtime scope

Unchanged:

- closed folder: `SBFolderIconImageView`;
- opened folder: `SBFolderBackgroundView`;
- App Library category card: `SBHLibraryCategoryPodBackgroundView`;
- SpringBoard-only injection;
- RootHide arm64e.

No daemon, timer, polling, DisplayLink, or continuous Metal rendering.
