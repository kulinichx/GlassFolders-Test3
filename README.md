# GlassFolders 0.7.4 Beta 2.3

Beta 2.3 is a controlled corrective pass with three locked targets. It does not resume App Library experimentation yet.

## 1. Liquid Glass closed folder — exact accepted baseline restore

The closed-folder visual path is restored to the earlier on-device reference that was explicitly accepted as the lighter look. This is not another alpha approximation.

The complete closed visual chain now matches that accepted implementation: closed optical lighting image, backdrop blur/saturation, neutral brightness lift, neutral-white transmission lift, passive `SBHLibraryCategoryPodBackgroundView` blend, and closed-folder layout behavior. No chromatic tint is added; wallpaper remains the color source.

At 55% strength, the restored Liquid Glass body includes roughly +1.3% neutral brightness and ~5.7% neutral-white transmission on top of the wallpaper-owned backdrop. Those neutral values are what the later versions accidentally removed, causing the closed folder to read too dark.

The detached App Library pod remains passive. `_updateVisualStyle` is not invoked.

## 2. Clear opened folder — locked reference behavior

Clear is treated as its own optical material, not a weak Liquid Glass preset. Purple, blue, pink, orange, green, and every other hue come only from wallpaper / desktop backdrop.

At 55% strength, the current target is approximately:

- Dark appearance: 1.43 pt local blur, 84% backdrop sample, +3.6% neutral brightness, ~4.9% neutral-white transmission.
- Light appearance: 1.23 pt local blur, 77% backdrop sample, +1.5% neutral brightness, ~2.3% neutral-white transmission.

Dark mode gets more neutral definition so Clear remains visible over dark wallpaper. Light mode reduces white energy to avoid an acrylic/milky card. No hue is injected in either mode.

## 3. Liquid Glass opened highlight continuity

The directional specular is modeled as two mirrored continuous rails:

- top -> upper-left corner -> left-side fade
- bottom -> lower-right corner -> right-side fade

The horizontal-edge/corner tangent is never a fade endpoint. The reflection turns through the owned corner, loses only a small amount of energy by the side tangent, then fades over about 1.12 corner radii using a C2 smootherstep. The lower-right/right relation is the exact 180-degree mirror of the upper-left/left relation.

The opened optical map remains cached at the established 1.5x render scale; no 2x/high-load experiment is reintroduced.

## Scope / stability

- no App Library controller hooks
- no `_updateVisualStyle` activation
- no daemon, timer, display link, gyro, or Metal render loop
- no chromatic body tint in Clear or Liquid Glass
- dark/light appearance changes material gain only; rail geometry remains identical
- real App Library is not modified in this pass
