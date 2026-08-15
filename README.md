# GlassFolders 0.7.4 Beta 3.3

Beta 3.3 is an App Library attachment fix.

## What was wrong in Beta 3.2

Beta 3.2 only initialized the exact `SBHLibraryCategoryPodBackgroundView`
hook when that private class was already available during tweak construction.
On the tested device the App Library remained stock, which means that path
was not a reliable lifecycle entry.

## Beta 3.3 strategy

The authoritative entry is now the page-level:

`SBLibraryViewController`

When App Library appears or lays out, GlassFolders:

1. marks the controller root as an App Library hierarchy
2. recursively scans only that hierarchy
3. finds the exact category background class when available
4. also accepts Library/Category/Background private-class naming variants
5. applies the independent App Library Glass material
6. keeps mini-folder/cluster views excluded from normal Clear/Liquid Glass

The exact `SBHLibraryCategoryPodBackgroundView` hook is retained only as an
optional fast path.

## Preferences

- `AppLibraryGlassEnabled` — default OFF
- `AppLibraryGlassStrength` — default 55
- use **应用并注销** after changing these settings

## Existing folder tuning

Clear and Liquid Glass optical constants are unchanged from Beta 3.1/3.2.

## Version / build

- package version: `0.7.4~beta3.3`
- artifact: `GlassFolders-0.7.4-Beta3.3-DEB`
