# GlassFolders 1.0.0

GlassFolders brings refined Clear and Liquid Glass materials to iOS folders and App Library, with independent controls for each surface and dedicated light/dark appearance tuning.

## Features

- Clear and Liquid Glass folder materials
- Independent Folder and App Library enable/disable controls
- Independent Clear and Liquid Glass strength controls for folders
- App Library modes: Follow Folder, Clear, or Liquid Glass
- Matched App Library category-card and search-field materials
- Tuned light and dark appearance
- English and Simplified Chinese Settings
- Standard rootless and RootHide build targets

## App Library

App Library uses fixed, tuned material recipes rather than exposing engineering presets:

- Clear uses the Apple Bright baseline
- Liquid Glass uses the Crystal baseline
- Follow Folder synchronizes the material family while preserving App Library-specific tuning

## Compatibility

- Package identifier: `com.kulinich.glassfolders`
- Version: `1.0.0`
- Minimum firmware declared by the package: iOS / iPadOS 16.0
- Section: Tweaks
- Settings integration: PreferenceLoader

Two build targets are produced by CI:

- Standard rootless: `iphoneos-arm64`, rooted under `/var/jb`, with universal `arm64 + arm64e` tweak and preference-bundle binaries
- RootHide: `iphoneos-arm64e`

## Settings icon resources

The Settings icon is shipped both inside `GlassFoldersPrefs.bundle` and beside the canonical PreferenceLoader entry. This preserves the resource lookup behavior validated on-device.

Canonical PreferenceLoader entry:

`Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`

PreferenceBundle icon resources:

- `GlassFolders.png` — 29×29
- `GlassFolders@2x.png` — 58×58
- `GlassFolders@3x.png` — 87×87

## Localization

- English (`en`)
- Simplified Chinese (`zh-Hans`)

Product/material names **GlassFolders**, **Clear**, and **Liquid Glass** remain unchanged in both languages.

## Build

GitHub Actions builds release packages with `FINALPACKAGE=1` and validates package identity, architecture, rootless layout, PreferenceLoader registration, PreferenceBundle metadata, localization resources, and Settings icon assets before uploading the `.deb` artifacts.

## Release

### 1.0.0

- Initial public release.
- Clear and Liquid Glass folder materials.
- Independent App Library glass controls and matching search/category materials.
- Light/dark appearance tuning.
- English and Simplified Chinese preferences.
- Standard rootless and RootHide package targets.
