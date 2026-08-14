# GlassFolders 0.5.6 / Test5.6 — Clean Edge Glass

## Visual change

Test5.5's broad diagonal specular highlight looked like a white stripe across
the folder on-device.

Test5.6 removes the diagonal/full-surface highlight entirely.

Liquid Glass now keeps:
- Backdrop Glass wallpaper sampling
- blur + saturation
- subtle overall border
- soft top-edge catch light
- soft left-edge catch light

There is no highlight layer spanning the interior of the folder.

## Performance

The change is lighter than Test5.5:
- two tiny perimeter gradient strips
- no full-surface gradient
- no animation
- no DisplayLink
- no timer
- no gyroscope

## Slider / haptics

Unchanged from Test5.5:
- 5% detents
- smooth drag
- crisp rigid tick when crossing a detent
- magnetic settle on release
- exact detent persistence

## Settings button

`应用并注销`
