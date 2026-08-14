# GlassFolders 0.7.4 Beta 2.2

Beta 2.2 deliberately changes three locked visual targets before the App Library phase resumes.

## 1. Liquid Glass closed-folder baseline

The closed Liquid Glass path is restored to the earlier proven light reference, not approximated with another alpha tweak. The later one-shot `_updateVisualStyle` activation for the detached `SBHLibraryCategoryPodBackgroundView` is removed completely. The pod remains a passive reusable visual view at the earlier blend (`min(0.78, 0.42 + 0.36*r)`), matching the older working closed-folder implementation.

No opened Liquid Glass material or rail geometry is changed in this step.

## 2. Clear opened-folder reference pass

Clear is rebuilt as its own material rather than a weak Liquid Glass preset or a completely unfiltered transparent sheet. The stock `SBFolderBackgroundView` material stays suppressed; our `CABackdropLayer` now applies only a shallow local Gaussian blur with partial sample opacity. Hue is never injected: purple, blue, pink, orange, green, and all other chroma come from the wallpaper / desktop behind the folder.

At the common 55% strength, Clear uses roughly a 2.7 pt local blur in dark appearance and 2.2 pt in light appearance, versus roughly 7 pt for Liquid Glass. Clear also receives a small neutral-white transmission lift (about 2.8% dark / 1.4% light at 55%) and a separate broad, soft white edge texture.

Dark appearance uses slightly stronger neutral brightness, saturation recovery, and white edge definition so the transparent sheet remains visible over dark wallpaper. Light appearance reduces all three so a bright wallpaper does not become a milky white card. These are luminance/contrast changes only; there is no chromatic tint.

## 3. Liquid Glass opened highlight continuity

The opened Liquid Glass highlight is treated as two symmetric continuous rails instead of separate corner/edge pieces: top -> upper-left arc -> left-side fade, and bottom -> lower-right arc -> right-side fade. The internal tangents keep full rail energy; fading starts only after the side tangent and uses the same C2 smootherstep length on both sides. Dark/light appearance changes gain only, never the geometry.

The opened optical map stays at the existing 1.5x cached render scale; this pass does not restore the higher-load 2x experiment.

## Stability / scope

- no App Library controller hooks
- no `_updateVisualStyle` activation in the closed folder path
- no daemon, timer, display link, gyro, or Metal render loop
- opened optical map stays at the existing 1.5x cached render scale
- Liquid Glass opened rail geometry changes only in the two locked continuity pairs; material/body parameters are unchanged by that rail pass
- real App Library is not modified in this pass
