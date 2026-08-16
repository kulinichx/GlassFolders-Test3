# GlassFolders 1.0.0

## Commercial Candidate FIX12 — PreferenceBundle Icon Resolution

FIX12 fixes the Settings root icon without changing the approved Dock Glass artwork.
The PreferenceLoader entry declares `bundle = GlassFoldersPrefs` and `icon = GlassFolders.png`; therefore the three icon PNGs are now also shipped inside `GlassFoldersPrefs.bundle` via `prefs/Resources/`. The nested PreferenceLoader copies are retained for compatibility, while stale top-level duplicates are removed during CI.


A refined glass-material tweak for iOS folders and App Library.

## Features

- Clear and Liquid Glass folder styles
- Independent Folder and App Library switches
- Adjustable Clear and Liquid Glass strength for folders
- App Library: Follow Folder / Clear / Liquid Glass
- Matched App Library category cards and search field
- Tuned light and dark appearance
- English and Simplified Chinese Settings
- RootHide arm64e and standard rootless arm64 build workflows

## App Library

App Library uses fixed, carefully tuned materials rather than exposing engineering presets:

- Clear uses the accepted Apple Bright baseline
- Liquid Glass uses the accepted Crystal baseline
- Follow Folder syncs the style family while preserving App Library-specific tuning

## Localization

- English (`en`)
- Simplified Chinese (`zh-Hans`)

Product/material names **GlassFolders**, **Clear**, and **Liquid Glass** remain unchanged in both languages.

## Package

- Identifier: `com.kulinich.glassfolders`
- Version: `1.0.0`
- iOS: `16.0+`
- Section: Tweaks

The previous test package `com.local.glassfolderstest3` is declared as conflicting/replaced to prevent both builds from installing over the same files.

## Release note

The 1.0.0 commercial candidate locks the visual baseline from the validated Beta 4.6 code. No optical formulas were retuned during productization.

---

# GlassFolders 1.0.0 中文说明

为 iOS 文件夹与 App 资源库提供精细调校的 Clear / Liquid Glass 玻璃材质。

## 功能

- 文件夹 Clear / Liquid Glass 两种样式
- 文件夹与资源库独立开关
- 文件夹 Clear / Liquid Glass 独立强度
- 资源库：跟随文件夹 / Clear / Liquid Glass
- 资源库分类卡片与搜索框统一材质
- 浅色、深色模式分别优化
- 英文 / 简体中文双语设置页
- RootHide arm64e 与标准 rootless arm64 构建流程

## 资源库

资源库不再暴露工程调试预设，而是固定使用已经确认的效果：

- Clear：Apple Bright 基线
- Liquid Glass：Crystal 基线
- 跟随文件夹：同步 Clear / Liquid Glass 样式，但保留资源库专属材质参数

## 正式包信息

- Package ID：`com.kulinich.glassfolders`
- Version：`1.0.0`
- iOS：`16.0+`

1.0.0 商业候选版只做产品化整理，不重新调整已经确认的视觉参数。

## Commercial Candidate FIX4

Fresh-install Settings registration fix:

- Restored `layout/Library/PreferenceLoader/Preferences/GlassFolders.plist`.
- The entry loads `GlassFoldersPrefs.bundle` through PreferenceLoader.
- GitHub Actions no longer deletes this required entry.
- Both RootHide and standard rootless verification jobs now fail if the
  PreferenceLoader entry is missing from the final `.deb`.

This addresses clean iOS/iPadOS 16.x installations where the package installs
but GlassFolders does not appear in Settings.

## Commercial Candidate FIX5

iOS/iPadOS 16.x Preference Bundle architecture fix:

- Standard rootless binaries now build as universal `arm64 + arm64e`.
- Debian package architecture remains `iphoneos-arm64`, as expected for rootless.
- GitHub Actions verifies both the tweak dylib and `GlassFoldersPrefs` bundle
  contain both `arm64` and `arm64e` slices.
- This fixes the Settings loader error:
  `have 'arm64', need 'arm64e'`.

No visual formulas or preference UI were changed.

## Commercial Candidate FIX6

Settings icon packaging fix:

- Added `GlassFoldersIcon.png` (29×29).
- Added `GlassFoldersIcon@2x.png` (58×58).
- Added `GlassFoldersIcon@3x.png` (87×87).
- Added `icon = GlassFoldersIcon.png` to the PreferenceLoader entry.
- GitHub Actions no longer deletes the icon assets.
- Both RootHide and standard rootless jobs verify all three icons exist inside the final `.deb`.

The icon uses the approved GlassFolders blue/purple Liquid Glass folder identity.

## Commercial Candidate FIX7

PreferenceLoader duplicate-entry cleanup:

- Restored the original canonical entry:
  `Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`
- Removed the accidental top-level entry introduced during FIX4/FIX6.
- Restored the canonical nested icon names:
  `GlassFolders.png`, `GlassFolders@2x.png`, `GlassFolders@3x.png`.
- GitHub Actions removes stale top-level duplicates before packaging.
- Final package verification requires exactly **one** GlassFolders
  PreferenceLoader entry.
- `GlassFoldersPrefs.bundle/Info.plist` is now updated to the commercial
  `com.kulinich.glassfolders.preferences` / `1.0.0` identity.
- FIX5 universal `arm64 + arm64e` rootless build remains enabled.

No visual material parameters were changed.


## Commercial Candidate FIX8

Settings icon visual refresh:

- Replaced the canonical nested PreferenceLoader icon set with the approved
  frosted-glass GlassFolders identity.
- Preserved the existing canonical filenames and sizes:
  `GlassFolders.png` (29×29), `GlassFolders@2x.png` (58×58), and
  `GlassFolders@3x.png` (87×87).
- Icons retain alpha transparency outside the rounded icon body for clean
  rendering in Settings.
- No tweak logic, preference behavior, package identity, localization,
  architecture settings, or GlassFolders visual material parameters were changed.

FIX7 single-entry PreferenceLoader cleanup and FIX5 universal
`arm64 + arm64e` standard rootless build behavior remain unchanged.

## Commercial Candidate FIX9

PreferenceLoader icon lookup compatibility fix:

- Keeps the single canonical PreferenceLoader entry plist at:
  `Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`.
- Moves the three Settings icon resources to the PreferenceLoader root:
  `Library/PreferenceLoader/Preferences/GlassFolders.png`,
  `GlassFolders@2x.png`, and `GlassFolders@3x.png`.
- Keeps `icon = GlassFolders.png` in the entry plist.
- GitHub Actions removes stale nested icon copies before packaging and verifies
  the root icon paths in both RootHide and standard rootless `.deb` outputs.
- Uses the approved FIX8 frosted-glass icon artwork without changing tweak logic,
  preference behavior, package identity, localization, or architecture settings.

This matches the icon lookup behavior confirmed on the target device, where the
PreferenceLoader entry is nested but the icon filename is resolved from the
`Preferences/` root directory.

## Commercial Candidate FIX10

Final Settings icon material refresh:

- Replaces the Settings icon artwork with the approved programmatic Dock-glass design.
- Uses a clean neutral graphite glass body with directional continuous edge highlights:
  upper-left corner into the top edge, and lower-right corner into the bottom edge.
- Left and right vertical edges remain deliberately subtle.
- Keeps the exact PreferenceLoader compatibility layout established in FIX9:
  `GlassFolders.png`, `GlassFolders@2x.png`, and `GlassFolders@3x.png` live directly in
  `Library/PreferenceLoader/Preferences/`, while the single entry plist remains at
  `Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`.
- Icon sizes remain 29×29, 58×58, and 87×87 with RGBA transparency outside the
  rounded icon body and neutral RGB in zero-alpha pixels to prevent dark edge halos.
- No tweak logic, preference behavior, package identity, localization, architecture,
  or GitHub Actions build logic was changed from FIX9.

## Commercial Candidate FIX11

PreferenceLoader icon co-location fix:

- Restores the canonical FIX7 PreferenceLoader resource layout.
- Keeps the single entry plist at:
  `Library/PreferenceLoader/Preferences/GlassFolders/GlassFolders.plist`.
- Places all three Settings icon files beside that plist:
  `GlassFolders.png`, `GlassFolders@2x.png`, and `GlassFolders@3x.png`.
- Keeps `icon = GlassFolders.png` unchanged so the icon filename resolves within
  the same PreferenceLoader resource directory as the entry plist.
- GitHub Actions now verifies the nested icon paths in both RootHide and standard
  rootless package outputs and continues to reject duplicate PreferenceLoader entries.
- The approved FIX10 Dock-glass artwork is preserved byte-for-byte; only its package
  location changed.
- No tweak logic, preference behavior, package identity, localization, or architecture
  settings were changed.

## Commercial Candidate FIX13

Final Settings icon visual refresh based on the approved Control Center glass study:

- Replaces the previous Settings icon artwork with the approved programmatic
  Control-Center-inspired frosted-glass design.
- Uses a low-frequency blurred multicolor underlay (slate/blue/green/neutral warm)
  beneath a cool frosted glass film to create visible transmitted color at small sizes.
- Preserves the approved continuous directional edge-highlight treatment:
  upper-left corner into the top edge and lower-right corner into the bottom edge,
  with deliberately subtle left/right vertical edges.
- Preserves the under-glass blurred `GF` mark, `Liquid Glass` title, switch geometry,
  rounded-square geometry, and alpha-transparent outside corners.
- Installs identical 29×29, 58×58, and 87×87 icon assets in both locations already
  validated by FIX12: `GlassFoldersPrefs.bundle` resources and the nested
  PreferenceLoader resource directory.
- No tweak logic, preference behavior, package identity, localization, architecture,
  or GitHub Actions lookup/verification logic was changed from FIX12.

