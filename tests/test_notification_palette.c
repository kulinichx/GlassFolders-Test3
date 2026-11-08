#include <stdio.h>
#include <stdlib.h>
#include "../GFNotificationPalette.h"

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    GFNotificationPalette white = GFNotificationPaletteForWallpaper(1, 1, 1, 1, false, false);
    GFNotificationPalette black = GFNotificationPaletteForWallpaper(0, 0, 0, 1, false, false);
    CHECK(white.valid && white.lightSurface && white.primaryWhite < 0.10);
    CHECK(black.valid && !black.lightSurface && black.primaryWhite > 0.95);
    CHECK(fabs(white.luminance - 1.0) < 0.000001);
    CHECK(fabs(black.luminance) < 0.000001);
    CHECK(white.secondaryWhite > white.primaryWhite);
    CHECK(black.secondaryWhite < black.primaryWhite);
    GFNotificationPalette gray = GFNotificationPaletteForWallpaper(.5, .5, .5, 1, false, false);
    CHECK(fabs(gray.luminance - 0.21404114048) < 0.000001);
    GFNotificationPalette middleLight = GFNotificationPaletteForWallpaper(.46, .46, .46, 1, true, true);
    GFNotificationPalette middleDark = GFNotificationPaletteForWallpaper(.46, .46, .46, 1, true, false);
    CHECK(middleLight.lightSurface && !middleDark.lightSurface);
    CHECK(!GFNotificationPaletteForWallpaper(NAN, 1, 1, 1, false, false).valid);
    CHECK(!GFNotificationPaletteForWallpaper(1, 1, 1, .5, false, false).valid);
    CHECK(!GFNotificationPaletteForWallpaper(-.1, 1, 1, 1, false, false).valid);
    CHECK(!GFNotificationPaletteForWallpaper(1, INFINITY, 1, 1, false, false).valid);
    for (int i = 0; i <= 1000; i++) {
        double input = i / 1000.0;
        GFNotificationPalette palette =
            GFNotificationPaletteForWallpaper(input, input, input, 1, false, false);
        CHECK(palette.valid);
        CHECK(palette.bodyOpacity >= 0 && palette.bodyOpacity <= .18);
        CHECK(palette.secondaryWhite >= 0 && palette.secondaryWhite <= 1);
        double body = input * (1 - palette.bodyOpacity) + palette.bodyWhite * palette.bodyOpacity;
        double background = GFNotificationLinearChannel(body);
        double text = GFNotificationLinearChannel(palette.primaryWhite);
        double contrast = (fmax(background, text) + .05) / (fmin(background, text) + .05);
        CHECK(contrast >= 4.5);
    }
    puts("Wallpaper palette: endpoints, golden luminance, hysteresis, invalid input, "
         "thin body and 1001 uniform-background primary contrast cases PASS");
    return 0;
}
