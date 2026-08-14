# GlassFolders 0.7.4 Beta 1.2 — Forced Theos SDK

Folder-only safety branch. No App Library code.

## Why this workflow exists

A GitHub log showed Theos building from `/Users/runner/theos`, even though the
previous clean workflow installed Theos under the repository workspace. That
proves an older `build.yml` was still being executed.

This clean repository intentionally uses the historical workflow filename:

`.github/workflows/build.yml`

so replacing that file overwrites the old workflow.

## SDK handling

The workflow downloads the official Theos patched
`iPhoneOS16.5.sdk.tar.xz`, extracts it, searches for the actual extracted
`iPhoneOS16.5.sdk`, and normalizes it to the exact path:

`$THEOS/sdks/iPhoneOS16.5.sdk`

Before compilation it verifies the exact directory again.

Both make commands explicitly receive:

`THEOS="$THEOS"`

so a stale runner environment cannot redirect Make to `/Users/runner/theos`.

## Runtime

Only:

- `SBFolderIconImageView`
- `SBFolderBackgroundView`

No App Library code or runtime loader exists.

## Settings icon

PreferenceLoader entry:

`icon = GlassFolders.png`

with matching 1x/2x/3x resources both next to the entry plist and inside
`GlassFoldersPrefs.bundle`.

The final deb verifier checks the actual packaged files.
