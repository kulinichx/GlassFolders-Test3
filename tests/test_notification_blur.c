#include <stdio.h>
#include "../GFNotificationBlur.h"
#include "../GFNotificationPalette.h"

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; \
} } while (0)

int main(void) {
    CHECK(GFNotificationBlurScale(0.0) == 0.0);
    CHECK(GFNotificationBlurScale(0.5) == 1.0);
    CHECK(GFNotificationBlurScale(1.0) == 2.0);
    CHECK(GFNotificationBlurScale(-100.0) == 0.0);
    CHECK(GFNotificationBlurScale(100.0) == 2.0);
    CHECK(GFNotificationBlurScale(NAN) == 1.0);
    CHECK(GFNotificationBlurScale(INFINITY) == 1.0);
    CHECK(GFNotificationBlurScale(-INFINITY) == 1.0);

    GFNotificationPalette white = GFNotificationPaletteForWallpaper(1, 1, 1, 1, false, false);
    GFNotificationPalette black = GFNotificationPaletteForWallpaper(0, 0, 0, 1, false, false);
    double previous = -1.0;
    for (int i = 0; i <= 1000; ++i) {
        double scale = GFNotificationBlurScale(i / 1000.0);
        CHECK(isfinite(scale) && scale >= previous && scale >= 0.0 && scale <= 2.0);
        previous = scale;
        CHECK(3.0 * scale <= 6.0 && 4.0 * scale <= 8.0 && 8.0 * scale <= 16.0);
        CHECK(white.lightSurface && white.primaryWhite == 0.07);
        CHECK(!black.lightSurface && black.primaryWhite == 0.98);
        double body = 1.0 - white.bodyOpacity + white.bodyWhite * white.bodyOpacity;
        CHECK(body >= 0.95 && body < 0.99);
    }
    puts("Notification blur: endpoints, finite/clamped/monotonic response and palette invariants PASS");
    return 0;
}
