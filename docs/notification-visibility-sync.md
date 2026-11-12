# Notification Material Visibility Synchronization

2026-11-13. The supplied 4.4-second device recording shows the notification
list moving out and back into view. Some card backgrounds and content fade
at different times. The recording alone cannot identify every native cause.

The replacement was a sibling of the native material, copying its alpha only
during layout. Native alpha/hidden changes between layouts could leave it stale,
and the stored hidden state only tracked reveals. The new binding forwards
MTMaterialView alpha and hidden requests to its managed replacement in the same
UIKit call. Unmanaged materials pass through. Our own suppression is distinguished
from native hidden requests; detach restores the latest native hidden state.
Empty notification bounds temporarily suspend the replacement without discarding
that state. No timer, frame polling, geometry or slider change is introduced.

UIKit validation uses the production binding with a material view double. It
exercises alpha and hide/reveal changes without layout, empty-bounds suspension,
restore/detach, and compares in-flight opacity with a normal UIKit reference
view. This does not execute iOS 16 SpringBoard's private material implementation.
The package is a targeted candidate; reproducing the original swipe on the
user's device remains the acceptance check.

## Follow-Up: Retention, Native Decoration And Swipe Actions

The user reports that the alpha/hidden synchronization candidate still flashes
and asks about the dark area at the bottom. It is not a confirmed resolution.
The subsequent screenshot also identifies opaque Options/Clear swipe buttons.

Two more code gaps are addressed without changing blur recipes or rim geometry:

- A known notification temporarily removed from its window used to restore the
  native material and destroy its glass. It now suspends and retains that glass
  until reattachment. Disable and unsupported presentations still restore native.
- The independent stack dimming overlay was only hidden during layout. Its
  managed hidden requests now remain suppressed at the class-specific setter.
  Known MTShadowView and MTMaterialShadowView decoration belonging to a managed
  notification platter is suppressed as well, including lazily created shadows.
  Detached/replaced decoration and disabled glass restore native visibility.

PLPlatterActionButton in a known notification action container now receives the
same notification glass recipe and SystemGlassStrength. Its original material
and separate tint view are suppressed. The production text state adjusts only
its identified title label to the wallpaper palette. Original control, targets,
highlight and swipe handling are retained; there is no new preference slider.
Unknown action contexts remain native. Live preference refresh includes actions.

Public RuntimeBrowser headers in qingralf/iOS16-Runtime-Headers were inspected
for PLPlatterActionButton, PLPlatterView, MTShadowView and MTMaterialShadowView.
These establish interface names, not their presence or behavior on build 20G75.
All private class hooks remain gated by compatible runtime superclass checks.

The UIKit harness now injects the actual production surface updater, state,
decoration logic, private-access helpers and text state into UIKit view doubles.
It exercises 100 detach/reattach cycles with glass identity retained, no-layout
decoration reveal attempts, lazy shadow creation/replacement, native restoration,
swipe scope, light/dark title contrast, hit testing and original action events.
Only material drawing, private view classes and palette lookup are stand-ins.
This is not an iOS 16 SpringBoard rendering test or an energy measurement.

The user's white-wallpaper screenshot shows dark notification content but white
right-hand dates. Date slots now use the same primary foreground as the content.
Scoped BSUIDefaultDateLabel color/attributed-text hooks preserve that foreground
when a managed date refreshes without notification layout, while retaining the
latest native values for restoration. Unmanaged labels pass through. A guard
prevents nested UIKit setter calls from overwriting native state with our color.
Foundation and UIKit tests cover repeated date recoloring, attributed strings,
preserved fonts, restoration and detach. No global UILabel hook is introduced.

Device acceptance still requires the reported scroll, checking for the flash
and late bottom shade, plus left-swiping a notification and trying both actions.
Also check right-hand dates after waiting for a system date update on both white
and dark wallpapers; lock-screen clock/status-bar styling is outside this change.

## Follow-Up: Date Output Filters

The user reports the previous date candidate did not resolve the device issue.
Across white/nonwhite wallpapers and light/dark modes, the date still appears
to follow interface mode while other notification text follows wallpaper.
The four-case observation is evidence of a mismatch, not proof of its cause.

The existing text state only removed filters named vibrantLight/vibrantDark.
It therefore left other date-layer output filters in place even after assigning
the same foreground as the body. NoisyFlake/Velvet2 at commit
3f2ccfe103e719474031ab254faa12a9c3f6e7ec provides a concrete reference:
src/Velvet2Colorizer.m, colorDate:, clears the date label's own filters before
setting its color. Its src/Tweak.x accesses the seamless content dateLabel.
This supports a date-local filter fix, not a claim about exact 20G75 internals.

The existing production text state now marks only the two identified date slots
and suppresses their own filter/compositing output while glass is active. It
retains the latest native values for restoration. Ordinary text still preserves
unknown filters, and ancestors, icons, unmanaged dates, clock and status bar are
not changed. Existing date callbacks and setter hooks are reused; no new hook,
timer, wallpaper rule or glass/shadow change is added.

Foundation tests exercise actual slot selection with date-only output filters,
100 native restyles per wallpaper/mode combination, both date locations, sibling
isolation and native restoration. UIKit uses production text state with real
CALayer/CAFilter objects for the same four combinations and restore checks.
These tests do not reproduce the private iOS 16 date renderer or establish that
the label was located on the user's phone. Device acceptance remains required.
