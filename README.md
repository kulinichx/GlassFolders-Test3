# GlassFolders 0.7.4 Beta 1.4 — Author Credit

This build adds the requested author attribution inside the GlassFolders
PreferenceBundle.

## Layout

At the very bottom of the settings page, after `应用并注销`:

- group title: `关于`
- static title/value row:
  - left: `作者`
  - right: `kulinich`

The row uses the native `PSTitleValueCell` pattern with a getter method:

`authorValue:`

It is informational only: no link cell, no chevron, no action.

## Runtime

SpringBoard tweak code is unchanged byte-for-byte from Beta 1.3.2.

Only the PreferenceBundle, version metadata and CI checks changed.

The folder-only safety branch remains:

- closed folder: `SBFolderIconImageView`
- opened folder: `SBFolderBackgroundView`
- no App Library code

Rounded settings icon and duplicate PreferenceLoader-entry cleanup are retained.
