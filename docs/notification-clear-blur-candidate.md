# Notification Clear-Blur Source Candidate

Historical fixed-radius candidate. The user's subsequent adjustable-control
request is implemented in [the blur-control candidate](notification-blur-control.md).
The tables below describe the earlier midpoint recipe, not the slider's range.

Date: 2026-11-13. Unreleased source change on the 1.3.4 baseline.
No package version was changed and no replacement DEB was built or installed.

User-confirmed test target: iPhone 14 Pro, iOS 16.6, build 20G75. This identifies
the intended test device; it does not verify the private compositor ABI. No SSH
connection is configured. The user approved pushing a separate test branch and
using the existing GitHub Actions workflow to build this low-blur candidate.

That build was subsequently put on hold at the user's request to study their
RC9 Dopamine material first, including white/black background visibility. A
local test branch was created, but no commit, push, CI dispatch or installation
was performed. See [the RC9 comparison](rc9-glass-material-comparison.md).

## Behavior

Only the existing adaptive notification recipe changes:

| Surface/state | Previous blur radius | Candidate radius |
| --- | --- | --- |
| Lock-screen notification, dark wallpaper | 8 | 4 |
| Home Screen banner, dark wallpaper | 8 | 4 |
| Either adaptive notification, light wallpaper | 3 | 3 |
| Banner inside an app, without wallpaper adaptation | 8 | 8 |
| Music and compatible Live Activity backgrounds | 8 | 8 |
| Flashlight/camera background | 3 | 3 |

Values are the project's Gaussian `inputRadius` settings, not measured Mango
defaults or a claim about Apple's reference screenshots.

`gfBackdropBlurRadius` selects the recipe for material refresh, palette changes,
and palette clearing. Clearing wallpaper adaptation restores radius 8; it must
not carry the Home Screen's lower blur into an app. The existing stack subclass
still changes decoration only and never rebuilds the material on stack changes.
Accessibility opt-outs and unknown wallpaper handling remain unchanged.

No rim geometry, highlights, body veil, tint, foreground colors, shadow, opacity,
capture group, folder, Dock, App Library, license, or preferences were changed.
The existing fallback material is also unchanged. This candidate does not add
live refraction, compositor hooks, screenshots, timers, or display links.

## Static Bridge Verification

`tools/inspect_mango_bridge.py` now repeats the Beta14-4 evidence checks. It
requires Capstone and the existing helpers in the sibling audit checkout.
It does not load the package code, output the embedded shader, or extract files.

```powershell
python -B tools/inspect_mango_bridge.py G:/QQDownload/com.go.mango_1.0-Beta14-4_iphoneos-arm64e_roothide.deb
python -B tests/test_mango_bridge_inspector.py -v
python -B tests/test_notification_lowwakeup2.py -v
```

The verifier rejects packages other than the recorded SHA256, verifies renderer
and shader identity, checks 19 selector call sites, 6 input-flow instructions,
25 compositor-flow instructions, and the command-buffer scanner anchor. It
interprets only the bounded version-setup instruction block. Unsupported
instructions, native calls, and arbitrary memory loads are rejected.

Its iOS 16 result is filter-type field `0x18`, input/auxiliary texture fields
`0x58`, and auxiliary-surface field `0x110`. The auxiliary-surface field is not
a command-buffer offset. These are observations of Mango's chosen layout, not
a tested runtime contract or production allowlist. No offsets are used by the
production tweak. Versions outside 16 in the report are setup-branch outputs,
not supported-system claims.

The sample separately discovers its command-buffer field by scanning code at
runtime. The verifier checks the static discovery/result-consumption path but
never runs that scanner, so its report leaves the target field offset null.
Output texture and command-buffer observations are detailed in
[the optics research](mango-beta14-optics-research.md#output-texture-and-command-buffer-discovery).

## Verification And Next Gate

- Local Python checks: 18 tests passed, covering notification source boundaries,
  unchanged rim/palette hashes, and verifier arithmetic/failure paths.
- Supplied Mango sample: hash, 19 selector calls, 6 input-flow instructions,
  25 compositor-flow instructions, scanner-anchor, and setup-block checks passed.
  The older Beta8 sample was correctly rejected by the exact package hash gate.
- C palette/Objective-C harnesses and actual iOS compilation still require the
  existing macOS/Theos CI environment; Windows has no usable Apple toolchain.
- No CI run, target GPU run, visual acceptance, or device energy measurement is
  claimed. Reduced blur still requires same-wallpaper front/rear notification,
  banner scene-transition, and small-text comparison on device.
- A standalone synthetic refraction demo already exists in the old checkout;
  adding another does not resolve the missing live compositor connection.
- Before enabling real displacement, validate the exact target system's
  QuartzCore identity, callback ABI, texture ownership/protection, output surface,
  and GPU lifetime with an identity pass. Then test only edge displacement while
  retaining our existing rim. No screenshot polling or unverified pointer offsets.
