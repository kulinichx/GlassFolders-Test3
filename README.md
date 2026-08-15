# GlassFolders 0.7.4 Beta 4.6

Beta 4.6 is the **Settings Cleanup** pass.

## Final settings layout

At the top of the page there are two independent master switches:

- 文件夹
- 资源库

Disabling folder glass no longer disables App Library glass.

### Folder

Folder controls stay simple:

- Clear / Liquid Glass
- Clear strength
- Liquid Glass strength

The strength descriptions are intentionally short.

### App Library

Only one public style selector remains:

- 跟随文件夹
- Clear
- Liquid Glass

The old Clear/Liquid preset pickers are removed from Settings.

Internally the accepted fixed presets are locked:

- Clear = Apple Bright
- Liquid Glass = Crystal

“跟随文件夹” follows only the normal folder style family. App Library keeps
its own accepted card/search material recipes.

## Visual baseline

Beta 4.6 does **not** retune the visual effects:

- light App Library = Beta 4.2 baseline
- dark App Library = Beta 4.3 baseline
- search/card unification = Beta 4.4 baseline
- follow-folder behavior = Beta 4.5
- desktop Clear / Liquid Glass optics = unchanged

## Version

- package: `0.7.4~beta4.6`
- artifact: `GlassFolders-0.7.4-Beta4.6-DEB`
