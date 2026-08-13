# GlassFolders 0.4 / Test4 — RootHide

Target validation environment:

- iPhone 14 Pro (iPhone15,2 / A16)
- iOS 16.6
- Dopamine 3.x RootHide-style environment

## What changed from stable Test3.1

Test3.1 proved that replacing `SBFolderIconImageView`'s assigned background view
is stable across repeated Home Screen page reuse.

Test4 keeps that exact architectural idea and adds only:

- master enable switch
- Home Screen glass strength slider (0–100)

No opened-folder hooks are included yet.

## Modes

### Enabled + Glass Strength 0%

Equivalent visual goal to Test3.1:
fully transparent folder icon plate.

### Enabled + Glass Strength 1–100%

Uses a tweak-owned `UIVisualEffectView` with
`UIBlurEffectStyleSystemUltraThinMaterial` plus a very light white tint.

The important part is that the Apple-provided original material background is
still replaced, so the page-reuse bug from Test3 should not return.

### Disabled

Passes SpringBoard's original background view untouched.

## Apply settings

For Test4, change settings and then Respring once.

This is deliberate. Real-time preference updates will only be added after the
basic preference bundle and custom glass view are verified stable on-device.

## What Test4 intentionally does NOT do

- no opened-folder panel changes
- no wallpaper backdrop changes
- no Liquid Glass edge highlight yet
- no folder layout/title changes
- no gestures
- no Dock hooks
- no launchd hooks
- no daemon
- no jailbreak filesystem access

## Suggested test sequence

1. Install over Test3.1.
2. Open Settings → GlassFolders.
3. Keep Enabled ON and Glass Strength at 0%.
4. Respring.
5. Swipe between Home Screen pages 20–30 times.
6. If stable, test 10%, then 20%, then 30%.
7. Disable the tweak, Respring, and verify the stock folder plate returns.

Only after all of the above is stable should we add opened-folder visuals.

## Upgrade note

The Debian package ID intentionally remains `com.local.glassfolderstest3`, so Test4 is treated as an upgrade from Test3.1 and dpkg can remove the obsolete Test3.1 dylib/plist cleanly.
