# GlassFolders 0.7.4 Beta 3.1

Beta 3.1 keeps the accepted **Clear Light V2** tuning and only refines **Liquid Glass**.

## Clear

No optical tuning changes in this pass.

- Clear remains high-transmission from the bottom of the slider.
- Light opened Clear keeps the accepted 28 pt local-blur ceiling.
- Dark Clear keeps the existing curve.
- `ClearStrength` remains independent from `LiquidGlassStrength`.

## Liquid Glass — closed, light appearance

The closed icon was reading too bright and too much like a pink/white card. Beta 3.1 makes the light appearance more wallpaper-owned:

- lower native `SBHLibraryCategoryPodBackgroundView` participation
- lower neutral-white tint
- much smaller brightness lift
- slightly lower local blur and saturation lift
- reduced closed optical-layer energy

Dark-appearance closed Liquid Glass keeps the previous baseline.

## Liquid Glass — opened, light appearance

The opened panel was transparent but visually grey and did not read strongly enough as glass. Beta 3.1 shifts the energy away from a uniform body and toward optical structure:

- lower local blur
- higher wallpaper saturation/chroma recovery
- stronger neutral backdrop luminance
- nearly full real-backdrop sampling
- thinner neutral-white body tint
- stronger top / upper-left directional rail
- weaker uniform side/bottom energy
- stronger localized lower-left specular glint
- weaker full-perimeter continuity border

The intent is **clear center + optical edge**, rather than **grey transparent sheet**.

## Version / build

- package version: `0.7.4~beta3.1`
- artifact: `GlassFolders-0.7.4-Beta3.1-DEB`
- existing preference keys and defaults are unchanged
- no new source files are added
