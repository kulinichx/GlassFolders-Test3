# GlassFolders 0.7.4 Beta 2.8

Beta 2.8 keeps Clear and Liquid Glass on independent saved controls, locks the accepted Liquid Glass baselines and the 40 pt opened-Clear blur curve, and raises ONLY light-appearance Clear neutral luminance/transmission more decisively. Dark Clear stays on the accepted calibration. Strong blur should look brighter and more translucent without becoming a white card, while wallpaper remains the sole hue source. App Library experimentation remains deferred in this pass.

## 1. Independent controls

The Settings page exposes two separate sliders:

- **Clear 模糊强度** -> key `ClearStrength`
- **Liquid Glass 强度** -> key `LiquidGlassStrength`

Changing one style no longer changes the stored strength of the other. Existing installations remain compatible: if either new key has never been written, the tweak reads the previous `GlassStrength` value as that slider's initial fallback. The old `GlassStrength` key is migration-only and is no longer shown as a slider.

## 2. Clear — high-authority opened blur

Clear is a colorless wallpaper-owned material. It does not inject purple, blue, pink, orange, green, or any other hue. Chroma comes from the real wallpaper / desktop backdrop.

`ClearStrength` primarily controls local Gaussian blur. Neutral-white transmission, edge highlight and saturation establish the Clear appearance early and then remain nearly constant, so increasing strength changes blur rather than simply making the panel whiter.

Opened Clear sits over SpringBoard's existing full-screen blur, so Beta 2.8 keeps the validated high-authority local range:

- 0%: 0 pt
- 10%: ~2.8 pt
- 25%: ~8.1 pt
- 50%: ~18.0 pt
- 55%: ~20.1 pt
- 75%: ~28.7 pt
- 100%: 40.0 pt

The curve uses `40 * strength^1.15`: the low end stays genuinely light, while the middle/high range separates strongly enough to remain visible over the host blur. The locally filtered backdrop is shown at ~99% opacity once Clear is active, preventing an unfiltered host layer from masking the slider's effect.

The same blur curve is used in light and dark appearance so a Clear percentage has one predictable blur meaning. Light/dark differences remain limited to neutral brightness, white transmission, saturation compensation and specular gain; hue is never changed.

### Light appearance optical calibration

Beta 2.8 leaves the 40 pt blur curve unchanged and changes only light-appearance Clear optics. Above the first 15% Clear activation, light mode now targets roughly **+7.0% neutral brightness**, **~5.8% neutral-white transmission**, **~1.075 saturation**, **0.77 soft specular opacity**, and a slightly stronger **~4.0% continuous white edge floor**. Dark mode remains on the accepted calibration: roughly **+4.1% neutral brightness**, **~5.1% neutral-white transmission**, **~1.065 saturation**, and **0.82 soft specular opacity**. These are neutral luminance adjustments only: wallpaper remains the sole hue source.

Closed Clear keeps its separately accepted response and is driven by the same independent `ClearStrength` setting.

## 3. Liquid Glass — independent composite strength, locked

`LiquidGlassStrength` remains the composite Liquid Glass control: blur, saturation, neutral-white transmission and specular response continue to scale together. It does not share a stored value with Clear.

The accepted lighter closed-folder implementation remains locked. It keeps the established backdrop blur/saturation, neutral brightness lift, neutral-white transmission lift, passive `SBHLibraryCategoryPodBackgroundView` blend and closed-folder optical lighting. The passive App Library category pod is not actively styled; `_updateVisualStyle` is not invoked.

## 4. Liquid Glass opened highlight continuity — locked

The opened directional specular remains the established mirrored continuous-rail model:

- top -> upper-left corner -> left-side fade
- bottom -> lower-right corner -> right-side fade

The corner/horizontal-edge tangent is not a fade endpoint. Side fade occurs only after the reflection has turned through the corner. Geometry is identical in dark and light appearance; only neutral optical gain changes.

The opened optical map remains cached at the established 1.5x render scale. No 2x/high-load experiment is used.

## Scope / stability

- Clear and Liquid Glass have independent stored strength values
- opened Clear strength is aggressively blur-dominant
- closed Clear response remains separately locked
- no chromatic body tint in Clear or Liquid Glass
- dark/light appearance uses separate neutral compensation
- accepted Liquid Glass closed/open visual baselines are locked
- no App Library controller hooks
- no `_updateVisualStyle` activation
- no daemon, timer, display link, gyro, or Metal render loop
- real App Library is not modified in this pass
