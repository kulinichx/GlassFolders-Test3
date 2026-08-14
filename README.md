# GlassFolders 0.7.4 Beta 2.5

Beta 2.5 separates Clear and Liquid Glass strength into two independent saved controls. The accepted Liquid Glass closed/open baselines stay locked; App Library experimentation remains deferred in this pass.

## 1. Independent controls

The Settings page now exposes two separate sliders:

- **Clear 模糊强度** -> key `ClearStrength`
- **Liquid Glass 强度** -> key `LiquidGlassStrength`

Changing one style no longer changes the stored strength of the other. Existing installations remain compatible: if either new key has never been written, the tweak reads the previous `GlassStrength` value as that slider's initial fallback. The old `GlassStrength` key is migration-only and is no longer shown as a slider.

## 2. Clear — strength is blur-dominant

Clear is a thin wallpaper-owned material. It does not inject purple, blue, pink, orange, green, or any other hue. Chroma comes from the real wallpaper / desktop backdrop.

`ClearStrength` primarily controls local Gaussian blur. Neutral-white transmission, edge highlight and saturation establish the Clear appearance early and then remain nearly constant, so raising blur does not simply turn the panel whiter.

Opened Clear uses a dedicated curve because the panel sits over SpringBoard's already-blurred opened-folder background. Approximate local blur values are:

- 0%: 0 pt
- 25%: ~2.57 pt
- 50%: ~5.31 pt
- 55%: ~5.87 pt
- 75%: ~8.13 pt
- 100%: 8.0 pt

The same blur curve is used in light and dark appearance so the Clear slider has one predictable meaning. Light/dark mode differences are limited to neutral brightness, white transmission, saturation compensation and specular gain; hue is never changed.

Closed Clear keeps its previously accepted blur response and is driven by the same independent `ClearStrength` setting.

## 3. Liquid Glass — independent composite strength

`LiquidGlassStrength` remains the composite Liquid Glass control: blur, saturation, neutral-white transmission and specular response continue to scale together. It no longer shares a stored value with Clear.

The accepted lighter closed-folder implementation remains locked. It keeps the established backdrop blur/saturation, neutral brightness lift, neutral-white transmission lift, passive `SBHLibraryCategoryPodBackgroundView` blend and closed-folder optical lighting. The passive App Library category pod is not actively styled; `_updateVisualStyle` is not invoked.

## 4. Liquid Glass opened highlight continuity — locked

The opened directional specular remains the established mirrored continuous-rail model:

- top -> upper-left corner -> left-side fade
- bottom -> lower-right corner -> right-side fade

The corner/horizontal-edge tangent is not a fade endpoint. Side fade occurs only after the reflection has turned through the corner. Geometry is identical in dark and light appearance; only neutral optical gain changes.

The opened optical map remains cached at the established 1.5x render scale. No 2x/high-load experiment is used.

## Scope / stability

- Clear and Liquid Glass have independent stored strength values
- Clear strength is blur-dominant
- no chromatic body tint in Clear or Liquid Glass
- dark/light appearance uses separate neutral compensation
- accepted Liquid Glass closed/open visual baselines are locked
- no App Library controller hooks
- no `_updateVisualStyle` activation
- no daemon, timer, display link, gyro, or Metal render loop
- real App Library is not modified in this pass
