# Adjustable Notification Blur Candidate

2026-11-13. Source candidate on the 1.3.4 baseline, not a released or installed
package. Intended device: iPhone 14 Pro / iOS 16.6 (20G75). The user requested
a compromise first version after the RC9 material study: adjustable blur and a
clearer transmitted background before attempting genuine live refraction.

## Control

Settings adds one independent **Notification Blur** slider (`NotificationBlur`)
for lock-screen notifications and Home Screen/app banners. It reuses the current
percentage cell with 5% release detents, persistence and live notification bridge.
It remains visible when the Home Screen/Lock Screen sections are collapsed.

The range is 0-100%, default 50%. This is a multiplier of each scene's recipe,
not a percent of opacity or an absolute Gaussian radius:

| Slider | Adaptive light notification | Adaptive dark notification | App banner without wallpaper adaptation |
| --- | --- | --- | --- |
| 0% | 0 | 0 | 0 |
| 25% | 1.5 | 2 | 4 |
| 50% (default) | 3 | 4 | 8 |
| 75% | 4.5 | 6 | 12 |
| 100% | 6 | 8 | 16 |

The default keeps the earlier low-blur candidate. At 0%, our Gaussian filter is
omitted; native/background blur outside our layer is not undone. The fallback
UIVisualEffectView instead scales alpha from 0 to 0.44 (0.22 at default); it is
not claimed to match a native Gaussian radius.

Music, Live Activities, quick actions, folders, Dock and App Library do not use
this slider. Their recipes and existing controls remain unchanged. The original
blur-control revision did not modify the preference controller implementation
or shared live-refresh bridge; the subsequent slider-layout fix is noted below.

## Visibility And Cost Boundaries

- The original rim geometry/highlights, neutral body and foreground/palette
  implementation are retained. Pure-white/pure-black adaptation does not depend
  on the slider or the system interface's light/dark mode.
- Existing wallpaper-provider validation, unknown-input native fallback,
  accessibility opt-outs, stack transitions and app-banner foreground remain.
- The native backdrop still uses existing capture groups and disables in-place
  filtering. There is no new screenshot capture, displacement pass, render loop,
  daemon or periodic polling.
- The existing debounced preference reload visits retained notification hosts.
  A cached applied radius allows those cards to update even when their palette
  is unchanged. Stable calls return without allocating/replacing filters. Stack
  changes remain decoration-only. An explicit full material refresh invalidates
  the cache because its superclass can replace the backdrop filters.

This is a reference-inspired visual candidate, not a recreation of Apple's
private implementation or a verified live-refraction effect. Lower blur can
retain background detail, but cannot make a uniform white/black source visibly
refract. No power-saving, frame-rate or battery-life measurement is claimed.

## Verification

Local Python discovery: 21 passing tests, 2 skipped. These check preference
wiring/localizations, notification-only scope, cache/source lifecycle, zero-blur
filter omission and unchanged rim/palette hashes, plus prior regression checks.
`git diff --check` passes.

Native C tests exercise finite/clamped/monotonic blur response. A macOS
Foundation harness extracts and executes the actual production radius/cache and
palette lifecycle methods, with mocked filter writes rather than a GPU. It
checks retained cards, unchanged-radius reuse, zero/fallback behavior, light/dark
switches, return to app-banner radius, explicit cache invalidation and unrelated
surface exclusion. These two tests are skipped on this Windows host; the CI
workflow now runs them on its existing Linux/macOS jobs.

The requested RootHide build completed successfully on
`fix/notification-lowwakeup2-clear-blur-20G75`, source commit
`d84e4b55d1ff5d4ae225be4176630e2471b1d2c2`, Actions run `43274583626`.
Both baseline checks and the macOS build/native harness job passed. The standard
rootless job was intentionally skipped.

Downloaded artifact: `LumaGlass_1.3.4_roothide-arm64e.deb`, 96,916 bytes.
SHA256: `511061ce5f465cc0554298c456f2700ab67cb6444a3469ba283c3a0136e4d271`.
The local hash matches the CI package hash. Read-only archive inspection verified
package identity/version, thin arm64e tweak and preferences binaries, exactly one
PreferenceLoader entry, the 0-100/default-50 slider, Chinese localization and new
blur selectors. Retired experimental renderer markers are absent.
Delivery directory: `DEB/11-13/LumaGlass-NotificationBlur-Test` in the parent
workspace. No device installation, GPU or energy test has been performed.
The internal version remains 1.3.4; this is a separately identified test artifact,
not a new public release. Device comparison must include 0/25/50/100%, white,
black, detailed and mixed wallpaper, overlapping notifications, Home/app banner
transitions, disable/restore, accessibility and fallback material behavior.

## Device Feedback Follow-up

The first device test reported a brief lock-screen appearance change while
swiping, and a clipped slider thumb near the minimum (shown at 15%).

The stack classifier previously treated any scale below 0.999 as a rear card,
including transformations on wrappers. That can change the rim's subdued state
during motion even when notification content remains visible. Classification
now uses only the existing signature-checked native content-hidden getter;
unknown hosts remain front cards. The native stack callback still runs and
refreshes the replacement, but no longer stores a transform-derived flag.
Rim geometry, palette recipes and blur-cache behavior are unchanged. This is a
targeted candidate fix, not confirmation that every device flicker has the same
cause; compositor/native shadow behavior has not been measured on the phone.

The percentage label no longer uses an opaque masking background. Slider layout
converts between contentView and the control's actual parent coordinate spaces,
reserves a separate value column, retains endpoint margins and disables clipping
on the slider itself. The existing native control, targets, preference writes,
5% release detents and haptics remain. This shared layout correction also applies
to the existing folder sliders.

New regressions check semantic rear-state classification and execute extracted
production stack-query/slider-layout methods on macOS with view doubles. They
cover animated scale/rotation, unknown hosts, translated wrappers, repeated
layout, several row widths and conventional thumb footprints at 0/5/15/50/100%.
These are state/coordinate tests, not actual UIKit thumb or device screenshots.

The motion/slider follow-up passed cloud native checks and package verification
at source `84efc56418fd8d9ca05574f7569d5d76fc63b7e2`, Actions run `43278906414`.
The separately retained `DEB/11-13/LumaGlass-NotificationBlur-MotionFix` package
is 96,444 bytes with SHA256
`94782c688bb0f40f7dfe9c29d779a1539eb1090f55f7d82cbea3dcff697852be`, matching
CI. Both its tweak and preferences binaries differ from the first blur-control
test package and were verified as thin arm64e. Device feedback is still needed.
