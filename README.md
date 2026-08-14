# GlassFolders 0.7.4 Beta 1.8 — Native App Library Pod Layer

This build targets the visual difference between the previous desktop folder glass and Apple's App Library category cards.

## Targeted system path

The App Library category background class is `SBHLibraryCategoryPodBackgroundView`. On modern iOS it inherits from `SBHVisualStylingView`, which is responsible for applying Apple's private visual-style set.

Beta 1.8 does **not** hook or modify the real App Library. Instead, each closed desktop folder creates an independent `SBHLibraryCategoryPodBackgroundView` and uses it as a visual layer inside the custom folder background. This lets SpringBoard configure the layer with the same system visual-styling machinery used by App Library category cards.

If that private class cannot be created on a particular build, GlassFolders simply keeps using the stronger CABackdrop fallback.

## Stronger body

The Liquid Glass fallback was also increased so the folder is stronger even without the native pod layer:

- Gaussian blur: substantially higher than Beta 1.7;
- wallpaper saturation: increased;
- neutral white lift: increased without turning the card fully milky;
- UIVisualEffect fallback upgraded from Ultra Thin to Thin Material for Liquid Glass.

## Stronger edge optics

The closed-folder SDF lighting map keeps the same Beta 1.7 topology but increases luminance:

- upper-left -> full top remains the primary continuous rail;
- full bottom -> lower-right remains the secondary continuous rail;
- upper-right and lower-left remain attenuated;
- the maximum optical peak and both rail gains are higher.

The opened-folder panel is intentionally left on the previous conservative `SBFolderBackgroundView` path to avoid expanding the stability surface.

## Safety / compatibility

- RootHide arm64e target retained;
- SpringBoard-only injection;
- private App Library class resolved with `NSClassFromString`;
- no direct private-framework link required;
- no App Library controller hooks;
- no daemon, timer, DisplayLink, gyro, or Metal render loop;
- existing cached CPU SDF optical maps retained.

Author: `kulinich`
