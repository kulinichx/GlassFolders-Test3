# GlassFolders 0.7.4 Beta 3.2

Beta 3.2 keeps the accepted **Beta 3.1 Clear / Liquid Glass optical tuning**
and adds a separate **App Library Glass** path.

## App Library separation

The previous normal-folder hook handled every `SBFolderIconImageView`.
That meant mini-folder / cluster views inside App Library could accidentally
receive the desktop Clear or Liquid Glass background.

Beta 3.2 explicitly separates these cases:

- normal desktop folder icon -> existing Clear / Liquid Glass
- opened normal folder -> existing Clear / Liquid Glass
- real App Library category background -> independent App Library Glass
- mini folder / cluster inside App Library -> Apple native transparent background

## App Library Glass

New independent preferences:

- `AppLibraryGlassEnabled` — default OFF
- `AppLibraryGlassStrength` — 0–100, default 55

The outer category-card path targets the real runtime class:

`SBHLibraryCategoryPodBackgroundView`

The new material uses:

- real wallpaper/backdrop color
- medium local blur
- restrained saturation/luminance lift
- very thin neutral-white tint
- subtle rounded glass border
- a small amount of Apple's native category-pod material blended above it

## Internal-pod safety

GlassFolders already creates a private copy of
`SBHLibraryCategoryPodBackgroundView` inside normal Liquid Glass folder icons.
Beta 3.2 marks that copy with an associated-object flag so the new real
App Library hook never touches it.

## Version / build

- package version: `0.7.4~beta3.2`
- artifact: `GlassFolders-0.7.4-Beta3.2-DEB`
- Clear / Liquid Glass preference keys and defaults are unchanged
- no new source file is added
