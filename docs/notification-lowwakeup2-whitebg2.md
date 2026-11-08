# LowWakeup2 WhiteBG Test 2

Date: 2026-11-08 (Asia/Shanghai). Status: source candidate; build and device
acceptance are recorded separately below.

## Installed Baseline

- User-confirmed installed package:
  `../DEB/10-28/com.kulinich.glassfolders_1.3.1~lowwakeup2_iphoneos-arm64e.deb`
  (path relative to repository root).
- Package bytes: 83,010.
- SHA256: `cc1f34308aef73e949d97951109373a8fc2d83b85270b5b93e12375885045543`.
- Source baseline recorded by the existing audit: `32b1022`.
- Isolated branch: `fix/notification-lowwakeup2`.
- Candidate version: `1.3.1~lowwakeup2+whitebg2`, RootHide arm64e.
- Preference short version: `1.3.1`; bundle build: `1.3.1.3`.
- Original packages, other worktrees, preferences domain and license key remain
  unchanged. This work does not silently move the user to the 1.3.2 source.

Matching the original hash to the existing audit identifies the recorded
baseline; it is not a reproducible byte-for-byte proof of source provenance.

## Implementation

The visual target is the supplied second screenshot: pale translucent body,
dark main text and quieter date text over light wallpaper. It is a project
approximation, not Apple's private Liquid Glass implementation.

- Read the cover sheet's `wallpaperColorProvider` /
  `averageColorForCurrentWallpaper`, then `_averageLockScreenWallpaperColor`.
  Fall back to the system legibility foreground's actual primary color.
  Do not use the device's dark/light interface mode as wallpaper brightness.
- Validate object-return signatures with the existing guarded getter before
  calling these optional private interfaces. If no usable color is available,
  preserve native material rather than invent a brightness value.
- Calculate sRGB luminance, with a 0.18 initial threshold and 0.16/0.185
  hysteresis. This uses a system wallpaper average, not a local per-card
  luminance sample; mixed wallpaper can still defeat a global decision.
- Cache color decisions per card and wallpaper generation; invalidate on
  cover-sheet legibility update, trait changes and accessibility events.
  No screenshot, frame timer, display link or new periodic work.
- Change only identified system notification text slots in classic/seamless
  content and the header. Treat dates/footer as secondary. Preserve fonts,
  geometry, strings, image attachments and icons.
- Replace only recognized `vibrantLight`/`vibrantDark` filters on those text
  layers while they are managed. Keep other filters and all ancestor filters.
  Save and restore original colors, attributed strings and modified filters.
- Child notification layout/text/date callbacks reapply scoped foreground
  colors, since a native date update can otherwise overwrite them without
  laying out the platter. No global UILabel/UIView hook.
- Body tint is 18% white on the light surface, 3.5% black on the dark surface;
  exposed rear cards use 40% of that tint. Retain the baseline 8 pt backdrop
  blur and narrow inner shade; reduce white rim glare on light surfaces.
  No high-opacity gray contrast slab.
- Scope new behavior to lock-screen notifications. Banners, quick actions,
  music, activities, Dock, App Library and folders retain baseline behavior.
- Reduce Transparency / Increase Contrast, unknown layout, missing foreground
  slots and unavailable brightness input preserve native material. Content-
  hidden rear cards can omit text slots.
- Remove the baseline's missing `GlassFoldersLarge.png` resource reference
  only so the preference bundle can build; other settings code is unchanged.

The selected palette is not a guarantee for arbitrary wallpaper, colored
attributed content, inherited vibrancy or OS versions. In particular, a
signature-compatible getter in a runtime dump is not proof that the user's
iOS 16 runtime exposes it. The fallback and diagnostic output make this
visible instead of claiming unverified success.

## Sources And Mango

Mango local binary inspection established separate rendering/tint controls,
black/white contrast selection in `MangoImageColorAnalyzer` called by a pill
component, and launcher text-shadow helpers. It did not establish a Mango
notification wallpaper-adaptation call chain. This candidate does not claim
to reproduce that unproven path.

Read-only interface references used:

- `MTACS/iOS-17-Runtime-Headers`: `CSCoverSheetViewController`,
  `CSWallpaperColorProvider`, `CSLegibilityProviding`, `_UILegibilitySettings`,
  `NCNotificationSeamlessContentView`, `NCNotificationContentView`,
  `PLPlatterHeaderContentView`, `MTVisualStylingProvider`.
- `nst/iOS-Runtime-Headers`: older notification/header text slots.
- `TrollStoreX/liquidass/Hooks/Platter.x`: foreground ownership/restoration
  reference; its fixed lock-screen white text is not used as adaptation.

These are static runtime/header references, not an Apple-supported ABI.

## Validation

- `tests/test_notification_lowwakeup2.py`: baseline fingerprints for original
  scheduler, settings, Makefile and public key. Stripping the three explicitly
  delimited notification additions must reproduce the full baseline Tweak hash.
- `tests/test_notification_palette.c`: actual production palette, golden
  luminance, hysteresis, invalid values and 6,006 primary/secondary contrast
  cases across 1,001 uniform gray backgrounds and three hysteresis states.
  These numerical checks do not represent real wallpaper texture.
- `tests/notification_foreground_harness.m`: actual production foreground
  state against Foundation-based view/text/layer doubles on macOS. Tests
  attributed text and fonts, native updates, filter restoration, scope,
  caching and invalidation. Does not emulate UIKit/Core Animation composition.
- Existing GitHub workflow compiles actual tweak and preferences with iOS
  16.5 SDK and checks package identity, architectures and resources.
- Diagnostic log prefix `[GlassFolders WhiteBG2]` reports input source,
  light/dark/native decision and managed text-slot count, without notification
  text, app names or sampled images.

Build status: PASS, run `42471454102`, source commit
`d6f6570f2b47473bc3b2fa0b8b96675fdffb8809`. Actual iOS tweak/preferences,
production state harness and package checks passed. RootHide job: 1m16s.
Only obsolete linker-option warnings appeared in the actual compilation.

Downloaded package:
`G:\AITEST\GlassFolders 1.0\DEB\11-8\kulinich.glassfolders_1.3.1-lowwakeup2-whitebg2.deb`,
90,184 bytes. Local SHA256 matches the successful remote build log:
`77fdcc54f46220d3b2e09dd8d43015ed93193e14e54db680e1437d3c6f66e555`.
Local package inspection independently checked version, thin arm64e tweak
and preferences, new foreground implementation, bundle version and single
Settings entry. Standard rootless was skipped intentionally.

Device acceptance: failed. On 2026-11-08 the user reported readable main text,
an almost invisible panel on white wallpaper and a flash during stack expansion.
The supplied screenshot also shows white timestamps. See
`notification-lowwakeup2-whitebg3.md` for the corrective candidate.

Initial builds `42470820490` and `42471095597` passed the production foreground
state harness but stopped at the official SDK browser download with HTTP 504,
before compiling the tweak. The official release API download was then tested
locally: release `theos/sdks`, tag `master-146e41f`, asset
`iPhoneOS16.5.sdk.tar.xz`, 17,446,920 bytes. SHA256:
`5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb`.
The workflow uses that API download and verifies this hash before extraction.

## Device Acceptance

Use the same light wallpaper and notifications as the user's first screenshot.
Check main text is dark, date is visibly secondary, wallpaper motifs still show
through and rear cards do not become bright slabs. Then compare dark and mixed
wallpaper, expand/collapse, incoming dates/content, hide previews, lock/unlock,
notification disable/enable and accessibility settings. Check banner and other
surfaces retain their baseline appearance. If native fallback remains, inspect
the diagnostic input and text-slot count before changing material opacity.

Rollback is the untouched original package in `DEB/10-28`; do not clear
preferences or activation. No device installation has been performed here.
