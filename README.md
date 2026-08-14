# GlassFolders 0.7.4 Beta 2.1

Beta 2.1 is a targeted closed-folder correction. It restores the lighter Liquid Glass closed-icon appearance shown in the earlier reference by reverting only the native App Library pod blend strength. Opened Liquid Glass continuity, Clear behavior, wallpaper-owned chroma, and dark/light adaptation remain unchanged in this release.

## Liquid Glass opened folder

The host panel is clipped with `kCACornerCurveContinuous`. Apple describes the continuous corner as a squircle-style corner, so a hand-rasterized circular edge can show a hairline tangent mismatch even when its segment masks are mathematically continuous. The current implementation therefore uses two layers of protection: the directional optical filament is centered slightly inside the clip, and a very faint native `CALayer` border supplies an exact continuous-corner continuity floor. The native border is not the visible highlight by itself; the white directional rails remain responsible for the Liquid Glass reflection.

This specifically targets upper-left corner -> top/left and bottom-right corner -> bottom/right continuity without returning to the expensive 2x lighting-map experiment. The cached opened-panel lighting map remains 1.5x.

## Clear opened folder

Clear now follows the supplied Apple reference instead of acting like a weak Liquid Glass preset. SpringBoard already blurs the presentation behind an opened folder, so Clear no longer applies a second local Gaussian blur. The panel is a transparent sheet with a neutral-white transmission lift plus soft white edge reflection. Purple, blue, pink, orange, and every other hue come only from the wallpaper / desktop behind it.

Dark appearance uses a stronger neutral transmission and edge definition; light appearance reduces both to avoid a milky white card. At 0% the Clear panel remains fully transparent.

## App Library path

The existing closed-folder App Library reuse remains enabled: an independent `SBHLibraryCategoryPodBackgroundView` is created for Liquid Glass folders and its own `_updateVisualStyle` is invoked after hierarchy/frame/radius are valid. The real App Library is not hooked or modified.

## Stability

No timer, display link, continuous CPU renderer, or 2x/3x opened-panel texture was added. The optical image remains cached and regenerated only for material-relevant changes.

## Beta 2.1 closed Liquid Glass correction

The native `SBHLibraryCategoryPodBackgroundView` remains in use, but its alpha is restored from the stronger Beta 1.9/2.0 blend (`min(0.90, 0.58 + 0.34*r)`) to the earlier lighter blend (`min(0.78, 0.42 + 0.36*r)`). This is intentionally the only closed-Liquid material change in this release.
