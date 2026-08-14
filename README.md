# GlassFolders 0.7.2 Beta 1 — Adaptive Open Glass

This build keeps the verified closed-folder path and adds the opened folder
through a deliberately narrow visual hook.

## Opened-folder architecture

The tweak hooks `SBFolderBackgroundView` only.

It does **not** hook:

- `SBFloatyFolderView`
- `_newPageBackgroundView`
- `setBackgroundAlpha:`
- `SBFolderControllerBackgroundView`

SpringBoard is allowed to create and animate its folder hierarchy normally.
When the real `SBFolderBackgroundView` reaches the window, the tweak:

1. clears only the background view's own dark fill;
2. keeps the stock material subviews alive but hides them;
3. adds one `CABackdropLayer`-backed glass child;
4. lets the native parent alpha/transform animate that child automatically.

No private factory return values are replaced and no transition methods are
overridden.

## Visual target

Opened Liquid Glass is a distinct rounded rectangle:

- transparent wallpaper color transmission;
- moderate frost, not a gray/white opaque card;
- softer and wider upper-left specular than the desktop folder;
- subtle right/bottom secondary rim and inner thickness;
- icons remain outside this visual background and therefore stay crisp.

## Dark / light appearance

The same Glass Strength slider drives both appearances.

Dark mode:
- slightly stronger brightness lift;
- slightly stronger neutral-white specular;
- enough transparency to avoid the stock deep-gray look.

Light mode:
- lower brightness and white tint;
- lower primary specular;
- slightly stronger far-side dark shoulder so the shape remains visible on a
  pale wallpaper.

The material refreshes through `traitCollectionDidChange:` only. There is no
timer or polling.

## Performance

No daemon, DisplayLink, timer, gyroscope, continuous Metal renderer, or
per-frame lighting calculation.

The large-panel optical map is generated at up to 1.5x scale and cached by
size/radius/5%-strength/appearance. The actual wallpaper transmission is
handled by `CABackdropLayer`.

## Build safety gate

GitHub Actions fails if the compiled tweak contains any of these paths:

- `SBFloatyFolderView`
- `_newPageBackgroundView`
- `setBackgroundAlpha:`
- `SBFolderControllerBackgroundView`

The dylib must contain only the intended folder visual classes:
`SBFolderIconImageView` and `SBFolderBackgroundView`.
