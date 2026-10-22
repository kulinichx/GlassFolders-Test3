# GlassFolders 1.3.0 — App Library and Dock glass candidate

This branch adds an independent offline GlassFolders issuer and device-bound activation. Candidate package: `1.3.0~lock14`. Target systems: iOS / iPadOS **16.0–17.3.1**, with a compatible jailbreak and SpringBoard injection environment. Device validation is still required; the source target is not a claim of tested compatibility.

See [离线授权、使用流程与兼容性检查](docs/离线授权与兼容性.md) and [Windows 签发器说明](tools/issuer/README.md). Issuer private keys and records must remain outside the repository. Existing RC7 licenses are not accepted. The previous 1.0.0-fix1 binary does not contain these changes.

For installation behavior, activation steps, and the console-free Windows launcher, see [安装状态与激活指南](docs/安装状态与激活指南.md).

The `license2` candidate moves activation into a dedicated License Management page. The home page prioritizes glass controls, shows a short activation prompt only while unactivated, and keeps a status link in About. Activated users can reveal the workflow with Change License; their current license stays saved until a replacement passes validation. Existing licenses and issuer keys remain compatible.

GlassFolders brings refined Clear and Liquid Glass materials to iOS folders and App Library, with independent controls for each surface and dedicated light/dark appearance tuning.

## Features

- Clear and Liquid Glass folder materials
- Independent Folder and App Library enable/disable controls
- Independent Dock switch with Hide Background / Glass Effect modes; off by default
- Opt-in lock-screen notification, flashlight/camera, music, and compatible Live Activity system backgrounds; see [锁屏玻璃使用与测试](docs/锁屏玻璃使用与测试.md)
- `lock2`: dedicated circular flashlight/camera optics and style/interaction refresh; grouped, non-in-place lock-screen backdrop filtering without additive card brightness, addressing overlapping-card washout reported on iOS 16.6 (device retest pending)
- `lock3`: lock-screen blur follows the selected folder style’s existing strength slider (lighter for circular controls), with stable edge lighting; subdued rear notification cards and guarded stack-overlay suppression target remaining bright rear strips (device retest pending)
- `lock4`: replace lock3 blur linkage with fixed lock-screen optics (6 pt cards / 3 pt buttons), clearer front edges and subdued rear cards; retain glass through Cover Sheet dismissal and cancelled swipes, including temporarily disabled quick actions (device retest pending)
- `lock5`: independent opt-in glass for system notification banners on the Home Screen and in apps, with a separate backdrop capture group; excludes banner scaling from rear-card detection (device retest pending)
- `lock6`: replace the wide lock-screen optical texture and uniform outline with a feathered, directional reflection, soft inward shoulder and shallow inner shade; share this rim with Home Screen/app banners, reduce rear-card lighting, and retain narrower circular-button optics. Fixed blur and folder independence remain unchanged (device retest pending).
- `lock7`: refresh short looks after their notification wrapper lays out, identify actual banner containers in addition to the private flag, resolve isolated wrapped materials, and observe delayed native background reveals. Cards use 8 pt blur, a faint neutral body veil and wider feathered inward edges; rear strips and circular buttons omit the veil (device retest pending).
- `lock8`: soften the inward card rim with pixel-spaced smoothstep coverage, a wider lower-peak shoulder and a shade that fades in before fading out. Restore collapsed-stack definition with a restrained reflection distributed along the lower edge. Preserve lock7 body/blur, foreground fine reflection, circular buttons and working banner routing. User reports lock7 glass and notification banners working on iPhone 14 Pro / iOS 16.6; lock8 edge refinement still requires device retesting.
- `lock9`: use the existing folder appearance as a visual reference for a thicker, compact card reflection (1.2 pt), while reducing the wide inward shoulder/shade and body haze. Rear notification strips receive a stronger lower rim and a faint black-only absorption veil for separation without additive whitening. Folder rendering, fixed blur, circular controls and banner routing remain unchanged; device retesting is required.
- `lock10`: after positive lock9 feedback, widen only the compact card reflection from 1.2 pt to 1.6 pt (1.4 pt on rear strips). Retain lock9 inward feathering, body density, lighting alpha and circular-button geometry; notification banners share the thicker rim. Device comparison is pending.
- `lock11`: address corner seams in the thicker rim by replacing adjacent subpixel reflection/shoulder rings with overlapping cumulative borders that share one native continuous outer curve. Compensated source-over opacity preserves the lock10 coverage profile and widths; no high-resolution card bitmap or additional backdrop blur. Circular controls and inner shade retain their existing geometry. User subsequently confirmed the lock11 appearance on iPhone 14 Pro / iOS 16.6; this is not validation of all target systems.
- `lock12`: adapt App Library category cards and the search pill to the accepted lock11 shared continuous rim, with compact 1.6 pt reflections, soft inward shoulders, overscanned background sampling and a lighter neutral body. Suppress native background haze with restoration on disable; retain native icons, text and input, independent switches and the three style modes. See [资源库玻璃使用与测试](docs/资源库玻璃使用与测试.md). App Library device retesting is pending.
- `lock13`: give App Library and glass-mode Dock a dedicated horizontal rim: stronger top/bottom reflections with radius-aware fading around the corners, nearly unlit side middles, and a compact wider bevel. Search pills use a narrower profile. Add restrained vertical body transmission; Dock uses fixed optics and a separate capture group independent of folder/App Library settings. Hide-background mode and lock11 notification/lock-screen rendering are preserved. Device comparison is pending.
- `lock14`: correct the overly bright, uniform rails seen in lock13 App Library and Dock device captures. Feather the reflection immediately, narrow the bright core, reduce shoulder/shade and body caps, and smoothly modulate light across the surface width. Preserve top/bottom emphasis with a faint connected side contour. Existing geometry, fixed blur, controls, folder/notification rendering and activation remain unchanged. Device comparison is pending.
- Independent Clear and Liquid Glass strength controls for folders
- App Library modes: Follow Folder, Clear, or Liquid Glass
- Matched App Library category-card and search-field materials
- Tuned light and dark appearance
- English and Simplified Chinese Settings
- Standard rootless and RootHide build targets

## App Library

App Library uses fixed, tuned material recipes rather than exposing engineering presets:

- Clear uses a fixed 10 pt blur and a slightly denser neutral veil
- Liquid Glass uses a fixed 8 pt blur and a lighter neutral veil
- Follow Folder synchronizes only the material family, keeping App Library independent of folder strength
- Category cards, the search pill and glass-mode Dock use a dedicated horizontal rim with surface-specific widths, adapted to native corner radii; native text, icons and interaction remain in place
- Top/bottom reflections vary gently across the width and ease around the corners into faint connected sides; a low-density neutral body avoids broad white caps

## Compatibility

- Package identifier: `com.kulinich.glassfolders`
- Candidate package version: `1.3.0~lock14`
- Minimum firmware declared by the package: iOS / iPadOS 16.0
- Maximum target: iOS / iPadOS 17.3.1 (package dependency `< 17.3.2`)
- Runtime/device validation: pending for this candidate; see the compatibility checklist above
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
