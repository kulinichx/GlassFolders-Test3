# Luma Glass 1.3.3

Date: 2026-11-08. Package identifier remains `com.kulinich.glassfolders`.
Source continues from the user's `1.3.1~lowwakeup2` baseline through WhiteBG3;
this is not a switch to an unrelated 1.3.2 branch.

## Requests And Scope

The user accepted the WhiteBG3 lock-screen appearance and asked to extend the
light-background treatment to Home Screen notification banners and App Library,
then requested a nicer public name. Public name: Luma Glass. Version: 1.3.3
(newer than the old 1.3.2 packages to avoid version-order ambiguity).

- Preserve the accepted lock-screen palette, blur radii, rim and stack behavior.
- Home Screen banners use the same light/dark palette, readable main/secondary
  colors and opt-in contour; light notification blur remains 3 pt.
- App Library category cards and search capsule use the same neutral light
  palette and contour. Light wallpaper uses 3 pt Liquid / 4 pt Clear blur.
  Dark/unknown wallpaper keeps the existing library recipe and horizontal rim.
- App Library labels, icons, search input and native text legibility remain
  system-owned. This change replaces background material only.
- Public package name, Settings entry, page title, About text and translated
  activation copy use Luma Glass. Binary names, preference domain, package ID,
  license verification and existing saved settings remain compatible.

## Background Input And Lifecycle

`GFHomeScreenPalette.h` reads the guarded `SBWallpaperController.sharedInstance`,
then `averageColorForVariant:1` for the Home Screen (lock-screen variant is 0).
Fallback reads `legibilitySettingsForVariant:1`, then
`SBUIController._currentHomeScreenLegibilitySettings`. Missing/invalid inputs
do not invent brightness from interface dark/light mode.

A shared cache serves all library surfaces and Home Screen banners, including
failed reads. Invalidate after `SBUIController._updateLegibility`,
SpringBoard `_updateHomeScreenPresenceNotification:`, notification trait and
accessibility changes. The existing queued live refresh applies changes to
visible surfaces. No new timer, screenshot or frame callback.

Banner adaptation requires the signature-checked
`UIApplication.sharedApplication.isShowingHomescreen` result. App banners
keep their prior recipe; a surviving Home Screen banner restores original
foreground and its prior recipe when returning to an app. Wallpaper average
must never be treated as the current app's background.

Separate banner and lock-screen backdrop groups are selected by the glass
subclass before any notification palette is applied. Stack dimming remains
exclusive to lock-screen notification cards.

The Home Screen input is a whole-wallpaper average, not a per-pixel analysis
of icons, widgets, folders or app content. Unknown private interfaces can
prevent adaptation. Runtime and visual acceptance remain separate from static
interface references and tests.

## Apple Mechanism And Evidence

Apple HIG Materials explains that standard materials, semantic vibrant colors
and foreground contrast are coordinated. Regular Liquid Glass blurs and adjusts
luminosity, and the WWDC25 session describes background-sensitive material and
foreground behavior. This is not equivalent to changing every label to black
when the device's interface is in light mode.

Read on 2026-11-08:

- Apple HIG Materials and official JSON:
  https://developer.apple.com/design/human-interface-guidelines/materials
- Apple WWDC25 session 219, Meet Liquid Glass:
  https://developer.apple.com/videos/play/wwdc2025/219/
- `MTACS/iOS-17-Runtime-Headers`, SpringBoard.framework:
  `SBWallpaperController.h`, `SBUIController.h`, `SpringBoard.h`.
  Confirms method shapes, not iOS 16 availability.
- `PoomSmart/BlurryBadges`, `Tweak.xm`:
  https://raw.githubusercontent.com/PoomSmart/BlurryBadges/master/Tweak.xm
  Actual Home Screen code calls `averageColorForVariant:1`.

No claim of porting Apple's private Liquid Glass shader or Mango notification
adaptation. The numerical palette remains this project's calibration.

## Validation

- Original scheduler, preference controller, license key and main-file
  non-notification baseline hashes remain protected.
- Existing actual palette, foreground/restoration, stack identity and rim
  render checks retained.
- Production foreground harness also exercises differing home/lock wallpapers,
  correct variant, shared caching, invalid input caching, system legibility
  fallback, Home Screen visibility and a rejected wrong-ABI getter.
- Production App Library header runs against view/filter test doubles with
  QuartzCore: light wallpaper in dark interface mode, category/search,
  repeated stable layouts, Clear/Liquid modes, wallpaper invalidation,
  accessibility opt-out and Dock exclusion.
- Actual tweak/preferences compilation and package checks validate the new
  public name, compatible internal identity, arm64e and one Settings entry.

Build and local artifact verification: PASS. Run `42474762013`, source
`4a9fb24446def0161bbec5da8546c405a16389d9`. RootHide job: 1m41s.
All production harnesses passed, followed by actual iOS tweak/preferences
compilation, package verification and artifact upload. Only existing obsolete
`-multiply_defined` linker-option warnings appeared during compilation.

Downloaded package:
`G:\AITEST\GlassFolders 1.0\DEB\11-8\LumaGlass-1.3.3\LumaGlass_1.3.3_roothide-arm64e.deb`.
Bytes: 93,784. SHA256:
`8996fe48576eb5d9933c2c756c261c12124f3785256b87808306f4d10bec545c`.
The local hash matches the successful build log. Local read-only DEB inspection
also confirmed the public names, compatible package ID, version 1.3.3,
preference build 1.3.3.1, thin arm64e tweak/preferences, home/library selectors,
About text and exactly one Settings entry. No device installation was performed.

Home Screen banner and App Library device acceptance: pending.
