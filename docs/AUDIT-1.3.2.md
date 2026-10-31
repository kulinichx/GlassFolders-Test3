# GlassFolders 1.3.2 Audit

Date: 2026-10-31 (Asia/Shanghai).

## Scope and Provenance

- Source baseline: `origin/fix/low-wakeup-1.3.1`, commit `32b1022`.
- Original package: `com.kulinich.glassfolders_1.3.1~lowwakeup2_iphoneos-arm64e.deb`.
- Original SHA256: `cc1f34308aef73e949d97951109373a8fc2d83b85270b5b93e12375885045543`.
- Isolated fix branch: `audit/low-wakeup-1.3.1`. Existing working copies are unchanged.
- Output version: `1.3.2`, RootHide/arm64e. Short artifact name:
  `kulinich.glassfolders_1.3.2.deb`.
- Source review, package structural inspection, portable regression guards,
  and remote build validation are distinct from device validation.

Package identity, bundle version, arm64e headers, SpringBoard-only injection,
single preference entry, and embedded license public key match this baseline.
These checks do not establish reproducible byte-for-byte source/binary provenance.
No issuer private key or issuer records were found among the package paths.
The release's public signing key and license wire format remain unchanged.

## Findings and Fixes

### P1: Quick-action superclass/subclass geometry churn

`GFPanelGlassView.layoutSubviews` assigned an overscanned sample of at least
30 pt and continuous corners; `GFQuickActionGlassView.layoutSubviews` then
reassigned 12 pt sampling, while `GFLockScreenGlassView` switched to circular
corners. Each later layout repeated both sets of changes. The source therefore
could not settle these properties to a stable value across its layout chain.

Fix: resolve quick-action geometry once in the panel layout. Use equality
guards for sample frames, corners, lock rim, and replacement-background state.
Keep the existing 12 pt quick-action sample and circular silhouette.
Actual wakeup/energy impact requires profiling on a device.

### P2: Closed folder live settings updated only the rim

The live bridge changed style/strength, but `GFBackdropGlassView.gfRefreshMaterial`
only invalidated the rim image. Blur, tint, and native Liquid Glass pod layers
remained from initialization. Enable/disable merely requested layout, with no
guaranteed `setBackgroundView:` call to restore the native background.

Fix: reuse the initialization recipes in a cached full material refresh,
including trait changes and transitions to zero strength. Retain each icon's
actual native background, restoring/replacing through its existing setter on
enable/disable. Preserve nil native backgrounds and App Library exclusions.

### P2: Open panel native background color was not restored

The panel forced `backgroundColor` to clear, but disabling only restored
hidden children. Native color writes while enabled were also discarded.

Fix: save the latest native color, distinguish nil from absent saved state,
exclude the tweak's own clear write, and restore the saved color on disable.
Clear stale saved colors when native writes happen after disable.

### P2: Slider debounce still scheduled one delayed wakeup per write

Generation checking skipped stale work but did not remove pending
`dispatch_after` callbacks. Every accepted update also queued an uncancellable
settling traversal. This reduced rendering work without bounding scheduled
delayed callbacks during a slider burst.

Fix: reuse one non-repeating dispatch source for both debounce and settling.
Disarm it with `DISPATCH_TIME_FOREVER` when idle. New writes replace the old
deadline; ignore already-enqueued stale expirations. This is event-driven,
not periodic polling. Guard the prelude constructor to SpringBoard too.

### P2: Zero-strength opened Liquid Glass retained old material

When strength became zero, neither material branch cleared the prior backdrop
filter chain or fallback blur. The previous nonzero recipe could remain.

Fix: clear old filters, hide sampling, and remove fallback blur in that branch.

### P2: App Library search unnecessarily reordered every layout

The search update always sent an existing overlay to the back, even when it
was already the first child; alpha, frame, and background writes were also
unconditional. This undermined the category-pod/Dock low-churn changes.

Fix: reorder and update visual properties only when they actually differ.
Also avoid rewriting unchanged App Library gradient locations.

### P2: Malformed Style preference could crash Settings

The preference UI called `integerValue` on an unvalidated CFPreferences
object. A dictionary/array stored under Style does not implement that selector.

Fix: require NSNumber, matching the runtime loader; otherwise select Clear.

### P2: Build referenced a missing icon resource

`prefs/Makefile` included `Resources/GlassFoldersLarge.png`, which does not
exist in the baseline tree. This is an invalid packaging input.

Fix: remove only that obsolete reference; preserve the three shipped icons.

## Automated Checks

Run `python3 tests/test_release_audit.py -v` with Node available. Guards cover
resource paths, runtime fix structure, release metadata, and production
scheduler block statements executed against virtual dispatch stubs. The
scheduler test covers 1,000 writes, a stale queued expiration, a preference
write during settling, and the idle infinite deadline. It does not emulate
libdispatch itself or UIKit.

Run `python3 tests/test_release_audit.py --deb PATH` for RootHide package
validation. It reads ar/tar without extraction and accepts binary plists.
GitHub Actions also compiles the actual tweak and preference bundle and runs
the existing architecture, layout, localization, and package checks.

## Device Acceptance Required

1. Upgrade from `1.3.1~lowwakeup2`; confirm an existing license remains valid.
2. On the Home Screen, toggle folders off/on without respring; check native
   restoration and no glass inside App Library mini-folders.
3. Switch Clear/Liquid Glass, change both strengths, test Liquid 55 -> 0 -> 55,
   and toggle light/dark appearance with closed and open folders visible.
4. Open a folder, disable its effect, and verify native color/material returns.
5. Test Dock hide/glass/off, App Library search/re-entry, and iPad rotation.
6. Test lock buttons idle/press/selected/disabled, lock music, stacked cards,
   banner appearance, cover-sheet dismissal, and a cancelled dismissal.
7. Compare identical idle/locked/slider scenarios before and after with device
   CPU/wakeup/energy tools. Record samples and SpringBoard crash logs.

No device test, measured energy improvement, full iOS 16-17 compatibility,
or guarantee against all private API changes is implied by a passing build.
