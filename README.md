# GlassFolders 0.7.3 Beta 1.3 — Runtime App Library Fix

This build addresses the repeated "App Library option enabled but visually
nothing changes" result.

## Structural issue in Beta 1 / 1.1 / 1.2

Those builds initialized the App Library Logos hook only when:

`objc_getClass("SBHLibraryCategoryPodBackgroundView")`

already returned a class during the tweak constructor.

If SpringBoardHome had not registered the App Library category-background class
at that moment, the hook group was skipped permanently. Entering App Library
later could not activate it.

## Beta 1.3 architecture

At SpringBoard startup, once:

1. explicitly `dlopen` SpringBoardHome;
2. try known category-background class names;
3. if needed, inspect registered classes for a very narrow candidate:
   - UIView subclass;
   - class name contains Library;
   - class name contains Background;
   - class name contains Category or Pod;
   - implements `_updateVisualStyle`;
4. select one best candidate only;
5. install Substrate method hooks on that one visual class.

No periodic scan or timer is used.

## Hooked behavior

Only visual lifecycle/style methods on the resolved background view:

- `_updateVisualStyle`
- `didMoveToWindow`
- `layoutSubviews`
- `traitCollectionDidChange:`
- `setBackgroundColor:`

No App Library controller, folder controller, search controller, icon-list, or
icon view is hooked.

## Existing functionality

Unchanged:

- closed Home Screen folder glass;
- opened folder glass;
- percentage-driven edge intensity;
- dark/light adaptation;
- integrated user-supplied settings icon;
- RootHide arm64e;
- SpringBoard-only injection.

No daemon, timer, DisplayLink, gyroscope, or continuous Metal renderer.
