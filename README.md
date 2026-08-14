# GlassFolders 0.7.4 Beta 1.3 — Dedup + Rounded Icon

This build fixes the two Settings issues observed on-device.

## Duplicate row

Inspection of the actual Beta 1.2 deb showed both:

- `Library/PreferenceLoader/Preferences/GlassFolders.plist`
- `Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`

The top-level plist was an old repository leftover and produced the second,
iconless GlassFolders row.

Beta 1.3 deletes that old file before every build and the final-deb verifier
hard-fails unless exactly one `GlassFolders.plist` exists.

Old `GlassFoldersIcon*.png` files are also deleted and rejected.

## Rounded Settings icon

Inspection of the actual Beta 1.2 PNG showed alpha=255 at all four external
corners. PreferenceLoader displayed the image as a square.

Beta 1.3 writes a real anti-aliased alpha mask into the PNG itself. The corner
radius is approximately 22% of icon width, matching the visual proportion of
standard iOS Settings list icons.

The final-deb verifier checks that the four external corner alpha values are
transparent for all three icon scales:

- 29x29
- 58x58
- 87x87

## Runtime

Unchanged folder-only safety branch:

- `SBFolderIconImageView`
- `SBFolderBackgroundView`

No App Library code.
