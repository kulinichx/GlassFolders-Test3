# GlassFolders 0.7.1 Beta 1.1 — Safe Optical

## Beta 1.1 build correction

Beta 1 accidentally lost the framework import block during source generation.
Beta 1.1 restores UIKit, CoreFoundation, QuartzCore, Objective-C runtime,
dispatch, and math imports. GitHub Actions now validates those imports before
compiling.


This build returns to the last stable architecture boundary.

## Runtime scope

Only the closed Home Screen folder icon is modified:

- `SBFolderIconImageView`
- `-setBackgroundView:`

Opened-folder customization is physically removed from this build.

## Optical edge model

Upper-left:
- neutral-white sub-point filament
- medium specular core
- broad low-contrast shoulder

Right/bottom:
- independent low-intensity transmitted rim
- darker shoulder begins farther inside the glass
- the dark shoulder therefore cannot cancel the visible rim

## Stability gate

The GitHub Actions workflow fails if the compiled dylib contains:

- `SBFloatyFolderView`
- `GFOpenedFolder`
- `_newPageBackgroundView`

## Performance

No daemon, Timer, DisplayLink, gyroscope, Metal render loop, or per-frame
lighting loop. The SDF optical texture is cached by size/radius/5%-strength.

## Opened folder

Opened folders intentionally remain stock in this build. The iOS 27-style
opened panel should be developed and validated separately from this stable path.
