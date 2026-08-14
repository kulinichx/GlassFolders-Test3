# GlassFolders 0.7.3 Beta 1.1 — App Library Fix

This is a focused correction of the App Library category-card path.

## Root cause addressed

Beta 1 called the original
`SBHLibraryCategoryPodBackgroundView -_updateVisualStyle` first, then tried to
hide stock UIView children and add custom glass.

That is insufficient if SpringBoard's category material is configured directly
on the host/background layer.

When App Library glass is enabled, Beta 1.1 does not call the stock visual-style
writer. It clears the host background and installs the custom glass directly.

When the option is disabled, the original method runs normally.

## Independent preference

`资源库大文件夹` now depends only on:

- master `启用`;
- `资源库大文件夹`.

It no longer requires the desktop Style selector to be `Liquid Glass`.

The current Glass Strength and dark/light adaptive calibration are still reused.

## Safety boundary

Still hooks only the category-card background class:

`SBHLibraryCategoryPodBackgroundView`

No App Library controller, category folder controller, icon-list, icon view,
search controller, or navigation hook is added.

Existing Home Screen closed/open folder code is unchanged.
