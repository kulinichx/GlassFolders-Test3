# GlassFolders 0.7.4 Beta 1 — Folder Only / Icon Focus

This build removes the experimental system-library page work completely.

## Runtime

Only two SpringBoard visual paths remain:

- `SBFolderIconImageView` for closed Home Screen folders;
- `SBFolderBackgroundView` for opened folders.

No other library/category/search/controller class is referenced.

## Settings

The experimental extra switch has been removed from the settings UI.

## Icon packaging

The user-supplied artwork is packaged twice as static resources.

PreferenceLoader:

- `GlassFolders/GlassFolders.plist`
- `GlassFolders/GlassFolders.png`
- `GlassFolders/GlassFolders@2x.png`
- `GlassFolders/GlassFolders@3x.png`

PreferenceBundle:

- `GlassFoldersPrefs.bundle/GlassFolders.png`
- `GlassFoldersPrefs.bundle/GlassFolders@2x.png`
- `GlassFoldersPrefs.bundle/GlassFolders@3x.png`
- `GlassFoldersPrefs.bundle/GlassFoldersLarge.png`

The final GitHub Actions verifier opens the real deb and confirms both copies
exist before publishing the artifact.

## Safety

- RootHide scheme;
- arm64e;
- SpringBoard-only main tweak injection;
- no daemon;
- no timer;
- no polling;
- no DisplayLink;
- no gyro;
- no continuous renderer;
- no experimental library-page hooks.
