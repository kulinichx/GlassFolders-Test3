# GlassFolders 0.5 / Test5 — RootHide

Target test environment:

- iPhone 14 Pro / iPhone15,2 / A16
- iOS 16.6
- Dopamine 3.x RootHide-style environment

## Goal

Add a usable Liquid Glass mode without turning GlassFolders into a large
SpringBoard customization suite.

The design intentionally favors low memory/GPU overhead over maximum visual
complexity.

## Modes

### Clear

Home Screen folder plate only.

- Strength 0%: equivalent to the stable Test3.1 clear plate.
- Strength >0: uses one ultra-thin material view per visible folder icon.
- No opened-folder hooks are visually applied in Clear mode.

### Liquid Glass

Home Screen:
- ultra-thin material
- very light white tint
- one static subtle border
- no shadow
- no animated gradient

Opened folder:
- reuses Apple's existing `SBFloatyFolderView` material
- only scales the system background alpha
- preserves Apple's own open/close animation
- creates no extra full-screen blur view

The surrounding wallpaper blur/dim remains entirely controlled by stock iOS.

## Performance decisions

There is deliberately:

- no daemon
- no DisplayLink
- no timer
- no live preference observer
- no custom animation loop
- no full-screen custom blur
- no shadow rendering
- no continuous gradient animation

Preferences are loaded once when SpringBoard launches. A Respring is required
after changing settings.

At Clear 0%, GlassFolders does not allocate a `UIVisualEffectView` for the
folder icon plate.

## Settings UI

The old inline slider numeric display is disabled because iOS 16's
PreferenceLoader was clipping the right-side decimal value on-device.

The stored range is still 0–100.

Suggested starting point for Liquid Glass: 35–55%.
