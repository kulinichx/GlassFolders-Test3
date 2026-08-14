# GlassFolders 0.7.3 Beta 1 — App Library Pods

This build adds one new independently controlled surface: the large category
cards on the App Library overview page.

## New preference

Settings → GlassFolders → App 资源库 → 资源库大文件夹

- default: OFF for upgrade safety;
- ON: applies the current Liquid Glass strength to App Library category cards;
- OFF: leaves the App Library category-card background stock;
- the master Enable switch still controls the whole tweak.

The App Library option currently applies to Liquid Glass mode only.

## Runtime boundary

The App Library implementation hooks only:

`SBHLibraryCategoryPodBackgroundView`

It does not hook App Library controllers, category-folder controllers,
pod icon views, pod icon-list views, search controllers, or navigation.

The background host keeps its system lifecycle. Its stock visual child views
remain allocated and are only hidden while custom glass is enabled.

## Material

App Library category cards reuse the large-surface `GFPanelGlassView`:

- wallpaper-driven `CABackdropLayer`;
- adaptive dark/light material;
- cached SDF optical map;
- top/bottom highlight rails;
- connected top-left/bottom-right corner highlights;
- current Glass Strength value.

Cards of the same size/radius/strength/appearance share the cached optical map,
so adding multiple App Library categories does not create a separate lighting
texture for every category.

## Existing behavior

Unchanged:

- closed Home Screen folder optical calibration;
- opened folder `SBFolderBackgroundView` implementation;
- 5% strength detents and haptics;
- RootHide arm64e build;
- SpringBoard-only injection.

No daemon, timer, DisplayLink, gyroscope, or continuous Metal rendering.

## Build safety

GitHub Actions rejects broader App Library controller/icon-list symbols and
requires `SBHLibraryCategoryPodBackgroundView` in the final tweak dylib.
