# GlassFolders 0.7.4 Beta 3.6

Beta 3.6 keeps the verified Beta 3.5 App Library attachment and changes only
the App Library material model.

## Why fixed presets

App Library fills most of the screen and contains many category cards plus the
top search control. A free 0–100 material percentage can easily make these
surfaces inconsistent, so Beta 3.6 removes the App Library strength slider.

Normal folder Clear and Liquid Glass percentage controls are unchanged.

## App Library style

### Clear

Default: **Apple Bright**

- Apple Bright — bright, luminous, clean frosted App Library reference
- Balanced — less white/luminance, more wallpaper-owned
- Soft — more blur and softer separation

### Liquid Glass

Default: **Crystal**

- Crystal — low blur/body tint, strong wallpaper transmission, thin optical edge
- Balanced — slightly more material body
- Deep — more blur/native material and a denser glass feel

The top search pill uses the same selected material as category cards, with only
a small interaction lift. It no longer receives the large brightness difference
used in Beta 3.5.

## App Library hierarchy

Unchanged:

- outer category cards -> App Library material
- top search pill -> same App Library material
- mini-folder / mini-cluster inside category cards -> Apple native transparent
- normal desktop/opened folders -> existing independent Clear / Liquid Glass

## Preferences

- `AppLibraryGlassEnabled`
- `AppLibraryStyle`
- `AppLibraryClearPreset`
- `AppLibraryLiquidPreset`

The old `AppLibraryGlassStrength` preference is ignored by the Beta 3.6 visual
model and is no longer exposed in Settings.

## Version

- package: `0.7.4~beta3.6`
- artifact: `GlassFolders-0.7.4-Beta3.6-DEB`
