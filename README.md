# GlassFolders 0.7.4 Beta 1.1 — CLEAN

This is a clean folder-only repository build.

## Runtime

Only the previously stable SpringBoard visual paths remain:

- closed folders: `SBFolderIconImageView`
- opened folders: `SBFolderBackgroundView`

All experimental App Library code is absent.

## Settings icon correction

GlassFolders uses a real PreferenceBundle (`GlassFoldersPrefs`).

For a bundle-based PreferenceLoader entry, the icon is now specified as the
bundle-relative resource name:

`GlassFolders.png`

The same 1x/2x/3x PNG set is explicitly packaged inside
`GlassFoldersPrefs.bundle`.

A second copy remains beside the PreferenceLoader plist for compatibility, but
the entry no longer depends on an absolute `/Library/...` icon path.

## GitHub Actions

This repository contains exactly one workflow:

`.github/workflows/glassfolders-074-clean.yml`

Its visible name is:

`GlassFolders 0.7.4 Beta1.1 CLEAN`

It downloads the official Theos patched iOS 16.5 SDK release directly and
verifies the SDK directory plus the patched Preferences framework before build.

The final deb is unpacked and checked for:

- arm64e tweak and PreferenceBundle binaries;
- SpringBoard-only filter;
- absence of all App Library/unsafe symbols;
- PreferenceLoader icon files;
- PreferenceBundle icon files;
- bundle-relative `entry.icon`;
- no maintainer scripts.

Do not merge this ZIP on top of an old Beta2.x repository without deleting old
workflow files first. The cleanest path is to replace the repository contents
with this tree.
