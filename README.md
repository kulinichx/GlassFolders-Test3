# GlassFolders 0.7.4 Beta 4.5

Beta 4.5 is the **App Library Follow Folder integration** pass.

## App Library style

The App Library style selector is now:

- **跟随文件夹**
- **Clear**
- **Liquid Glass**

Default: **跟随文件夹**

### Follow Folder

When selected, App Library reads the normal folder style directly:

- normal folder Clear -> App Library Clear
- normal folder Liquid Glass -> App Library Liquid Glass

The App Library keeps its own compact card/search material presets; only the
style family follows the normal folder.

### Forced styles

Selecting Clear or Liquid Glass forces that style only for App Library,
independent of the normal folder style.

## Visual baseline locked

No visual retuning in Beta 4.5:

- light App Library cards: Beta 4.2 baseline
- dark App Library cards: Beta 4.3 baseline
- search/card material unification: Beta 4.4 baseline
- desktop folder Clear/Liquid Glass: unchanged

## Compatibility

The old `AppLibraryStyle` preference is still read for compatibility, but the
new UI uses `AppLibraryStyleMode`:

- 0 = Follow Folder
- 1 = Clear
- 2 = Liquid Glass

## Version

- package: `0.7.4~beta4.5`
- artifact: `GlassFolders-0.7.4-Beta4.5-DEB`
