# GlassFolders 0.7.4 Beta 1.9

Beta 1.9 is a cleanup release focused on making the two selectable opened-folder styles genuinely different and on keeping package/version metadata synchronized with the code.

## Opened folder: Clear

Clear no longer replaces the whole panel with a fully weighted second blur. The folder presentation is already blurred by SpringBoard, so Clear now uses a very small local Gaussian kernel and blends that filtered backdrop back over the underlying presentation at partial alpha. This keeps the panel transparent and prevents a dark wallpaper from turning into a large purple/blue milky sheet.

- wallpaper/backdrop remains the only chromatic source;
- no purple, blue, pink, or other hue tint is added;
- only a very small neutral-white transmission lift is used;
- white specular rails remain;
- dark and light interface appearances use separate optical strengths.

## Opened folder: Liquid Glass

Liquid Glass remains the thicker material, but the dark-mode blur kernel has been reduced from the previous overly dark response. A small neutral brightness compensation and neutral-white transmission lift keep bright wallpaper information alive through the thicker blur without introducing a color tint.

- thicker blur than Clear;
- restrained saturation recovery;
- neutral brightness compensation, stronger in dark appearance;
- stronger white specular rails than Clear;
- separate dark/light appearance tuning.

## Continuous edge optics

The established continuous-rail geometry is retained: the upper-left corner joins both the top and left continuation, and the lower-right joins both the bottom and right continuation. The 1.5x cached CPU lighting map is retained for stability; Beta 1.9 does not bring back the heavier 2x render experiment.

## App Library category material

Closed Liquid Glass folders continue to create an independent `SBHLibraryCategoryPodBackgroundView`, attach it to the folder background, and trigger its own `_updateVisualStyle` only after frame/radius/hierarchy are valid. Beta 1.9 increases the native pod visual's participation so it contributes more of the App Library card material. The real App Library is not hooked or modified.

## Safety / compatibility

- RootHide arm64e target retained;
- SpringBoard-only injection;
- private classes resolved dynamically;
- no App Library controller hooks;
- no daemon, timer, DisplayLink, gyro, or Metal render loop;
- opened-panel lighting map remains cached at a maximum of 1.5x.

Author: `kulinich`
