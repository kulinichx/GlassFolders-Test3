# GlassFolders 0.7.4 Beta 2.4

Beta 2.4 is a controlled Clear-style tuning pass. The accepted Liquid Glass closed/open baselines remain locked; App Library experimentation is still deferred.

## 1. Clear — Glass Strength primarily controls blur

Clear is treated as a thin wallpaper-owned material. It does not inject purple, blue, pink, orange, green, or any other hue. Chroma comes from the real wallpaper / desktop backdrop.

The Glass Strength slider now has one dominant job in Clear: local Gaussian blur. Neutral-white transmission, edge highlight and saturation establish the Clear appearance early and then stay nearly constant, so increasing strength does not simply make the panel whiter or brighter.

Opened Clear blur curve:

- 0%: 0 pt local blur
- 25%: ~1.21 pt dark / ~1.09 pt light
- 50%: ~2.25 pt dark / ~2.04 pt light
- 55%: ~2.45 pt dark / ~2.22 pt light
- 75%: ~3.24 pt dark / ~2.93 pt light
- 100%: 4.20 pt dark / 3.80 pt light

At the 55% reference point, backdrop sampling stays high (~84% dark / ~79% light). Dark appearance uses a little more neutral brightness and white transmission so the thin glass remains legible over dark wallpaper; light appearance reduces that neutral energy to avoid a milky acrylic card. Neither mode changes hue.

Closed Clear follows the same slider semantics: strength is blur-dominant while neutral optics settle early. The 55% closed-Clear blur remains essentially at its previous visual baseline (~4.9 pt), avoiding an unrelated closed-state appearance change.

## 2. Liquid Glass closed folder — locked accepted lighter baseline

The accepted lighter closed-folder implementation remains unchanged. It keeps the established backdrop blur/saturation, neutral brightness lift, neutral-white transmission lift, passive `SBHLibraryCategoryPodBackgroundView` blend and closed-folder optical lighting.

At 55% strength the Liquid Glass body still includes roughly +1.3% neutral brightness and ~5.7% neutral-white transmission. The passive App Library category pod is not actively styled; `_updateVisualStyle` is not invoked.

## 3. Liquid Glass opened highlight continuity — locked

The opened directional specular remains the established mirrored continuous-rail model:

- top -> upper-left corner -> left-side fade
- bottom -> lower-right corner -> right-side fade

The corner/horizontal-edge tangent is not a fade endpoint. Side fade occurs only after the reflection has turned through the corner. Geometry is identical in dark and light appearance; only neutral optical gain changes.

The opened optical map remains cached at the established 1.5x render scale. No 2x/high-load experiment is used.

## Scope / stability

- Clear slider is blur-dominant
- no chromatic body tint in Clear or Liquid Glass
- dark/light appearance uses separate neutral compensation
- accepted Liquid Glass closed/open visual baselines are locked
- no App Library controller hooks
- no `_updateVisualStyle` activation
- no daemon, timer, display link, gyro, or Metal render loop
- real App Library is not modified in this pass
