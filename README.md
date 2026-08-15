# GlassFolders 0.7.4 Beta 2.9

Beta 2.9 changes only the Clear contract. Liquid Glass stays on the accepted Beta 2.8 baselines.

## 1. Independent controls

The Settings page keeps two separate saved sliders:

- **Clear 强度** -> key `ClearStrength`
- **Liquid Glass 强度** -> key `LiquidGlassStrength`

Existing installs remain compatible. If either split key has never been written, the old `GlassStrength` value is still used as the migration fallback.

## 2. Clear — high-base transmission, structure-driven strength

Clear no longer starts from a dull/grey optical state.

Selecting Clear now establishes the clean/transmitted look immediately, including at `ClearStrength = 0`. The slider does **not** ramp Clear from grey to transparent. Instead it mainly adds:

- local Gaussian blur
- wallpaper/chroma separation
- optical edge definition
- a small amount of additional neutral luminance

The opened blur curve is unchanged:

- 0%: 0 pt
- 10%: ~2.8 pt
- 25%: ~8.1 pt
- 50%: ~18.0 pt
- 55%: ~20.1 pt
- 75%: ~28.7 pt
- 100%: 40.0 pt

The curve remains `40 * strength^1.15`.

### Opened Clear baseline

At 0%, the locally sampled backdrop is already shown at about 99% alpha instead of being gated off. Neutral brightness and white-light transmission also begin near their final Clear values.

As the slider rises, the larger changes are saturation/separation, local blur and edge/specular structure. The white/transmission component moves only slightly, so high Clear should become more structured rather than simply whiter.

### Closed Clear baseline

Closed-folder Clear follows the same rule: 0% is still a real Clear material instead of a fully transparent replacement view. Blur begins at 0, while the colorless clean/saturation/luminance baseline is already present.

## 3. Liquid Glass — unchanged

`LiquidGlassStrength` keeps the Beta 2.8 composite behavior and accepted closed/open visual baselines. Blur, saturation, neutral-white transmission, passive `SBHLibraryCategoryPodBackgroundView` participation and Liquid Glass specular behavior are not recalibrated in this pass.

## Scope / stability

- Clear and Liquid Glass keep independent saved strength values
- opened Clear keeps the validated 0–40 pt blur curve
- Clear 0% now keeps a high-transmission clean baseline
- Clear strength mainly adds blur, separation and optical structure
- no chromatic Clear body tint
- Liquid Glass constants are unchanged
- no App Library controller hooks
- no `_updateVisualStyle` activation
- no daemon, timer, display link, gyro, or Metal render loop
