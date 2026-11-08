# Luma Glass 1.3.4

Date: 2026-11-08. Scope: App Library native foreground adaptation only.
The accepted WhiteBG3 lock-screen rendering and 1.3.3 glass optics are unchanged.

## Diagnosis And Limits

Version 1.3.3 adapted App Library backgrounds but deliberately left foregrounds
system-owned. The user reports that Library text remains light over light
wallpaper. This does not prove that the tweak set that text to white: the
previous implementation did not write Library text colors.

Runtime declarations identify a distinct native routing path:
`SBHLibraryViewController.effectiveLegibilitySettings` and
`_updateViewControllerLegibility`, plus `SBIconLegibilityLabelView`'s image-label
rendering. Library effective/override settings need not match the Home Screen
settings used outside the Library. A blanket UILabel recoloring would not
address that path.

This repair reconnects the library's effective legibility to the current
system Home Screen settings while Library glass is enabled. The full native
settings object is passed through, keeping its foreground, shadow and
image-label parameters. It does not construct black/white settings from a
wallpaper-average threshold or mutate global/private shared settings.

Search fields have a separate native visual-styling path. Only
`SBHSearchTextField` inside a confirmed Library hierarchy receives a local
Light/Dark appearance matching the native foreground polarity, followed by
its own `updateVisualStyling`. UIKit remains responsible for text, placeholder
and search/clear icon styling. No textColor, attributed content, icon pixels,
filters, global tint or other views are rewritten.

## Lifecycle And Failure Handling

- Signature-check both native controller methods before installing the getter
  hook, and check the search class/method before its scoped hooks.
- Prefer `SBUIController._currentHomeScreenLegibilitySettings`; fall back to
  `SBWallpaperController.legibilitySettingsForVariant:1`.
- Require a real `_UILegibilitySettings` object and a finite opaque UIColor
  primary color. Missing/wrong inputs keep native behavior, not invented colors.
- Cache valid and invalid provider reads until native Home wallpaper/legibility
  invalidation. Native settings objects are never modified.
- Propagate native controller settings on changes, including in-place settings
  updates signaled by a generation change; stable layouts do not rebuild labels.
- On disable, accessibility opt-out, replaced search capsule or reparenting,
  return native settings and restore the search field's saved appearance.
  Restoration does not overwrite a newer native appearance.
- No timers, per-frame callbacks, screen capture or global UILabel/UIView hooks.
- Preserve original baseline hashes by stripping seven explicitly delimited
  Library additions as well as the three existing notification additions.

## References

Public runtime declarations read 2026-11-08 from
`MTACS/iOS-17-Runtime-Headers` on GitHub:

- `PrivateFrameworks/SpringBoardHome.framework/SBHLibraryViewController.h`
- `PrivateFrameworks/SpringBoardHome.framework/SBHSearchTextField.h`
- `PrivateFrameworks/SpringBoardHome.framework/SBHSearchBar.h`
- `PrivateFrameworks/SpringBoardHome.framework/SBIconLegibilityLabelView.h`
- `PrivateFrameworks/UIKitCore.framework/_UILegibilitySettings.h`
- `PrivateFrameworks/SpringBoard.framework/SBLibraryViewController.h`

These declarations establish interface shapes, not iOS 16 availability or
Apple's private Liquid Glass implementation. Runtime guards fail closed.
Actual SpringBoard propagation and search glyph/placeholder behavior still
require device validation.

## Verification

Production Foundation harness covers native object identity/shadow preservation,
controller propagation, reentrancy, stable-layout caching, in-place settings
updates, search appearance/restoration, reparenting, unrelated-view exclusion,
accessibility, invalid data caching and rejected ABI signatures.

Retain existing palette, foreground, stack, material and rim tests, actual iOS
compilation, and DEB metadata/architecture/single-entry checks.

Build and artifact verification: PASS. Run `42477497139`, source
`00cbfeb4632d22e795bcd369a15ecd2ff2009b88`. RootHide job `128722006109`
completed in 3m39s. All production harnesses passed, followed by actual iOS
tweak/preferences compilation, package checks and artifact upload. Compilation
reported only the existing obsolete `-multiply_defined` linker warnings.

Downloaded artifact:
`G:\AITEST\GlassFolders 1.0\DEB\11-8\LumaGlass-1.3.4\LumaGlass_1.3.4_roothide-arm64e.deb`.
Bytes: 96,656. SHA256:
`1f55a45e15d04318dc61502ec74199ba4a7e5504d308460b71628a0fad987def`.
Local SHA matches the successful build log. Read-only local DEB inspection
confirms public name Luma Glass, package ID `com.kulinich.glassfolders`, version
1.3.4, preference build 1.3.4.1, thin arm64e tweak/preferences, native Library
routing markers and exactly one compatible Settings entry.

No phone connection or installation was performed. Device acceptance remains
pending: white/dark wallpaper title and placeholder polarity, native search
glyph styling, disabled-state restoration and return from expanded categories.
