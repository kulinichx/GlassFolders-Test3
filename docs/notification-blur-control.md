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
this slider. Their recipes and existing controls remain unchanged. No preference
controller implementation or shared live-refresh bridge was modified.

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

The user has now requested a package build. The candidate is being submitted on
`fix/notification-lowwakeup2-clear-blur-20G75` to the existing Actions workflow;
build/package verification and download results will be recorded below when
available. No device installation, GPU or energy test has been performed.
The internal version remains 1.3.4; this is a separately identified test artifact,
not a new public release. Device comparison must include 0/25/50/100%, white,
black, detailed and mixed wallpaper, overlapping notifications, Home/app banner
transitions, disable/restore, accessibility and fallback material behavior.
