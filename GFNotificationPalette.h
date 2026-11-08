#ifndef GF_NOTIFICATION_PALETTE_H
#define GF_NOTIFICATION_PALETTE_H

#include <math.h>
#include <stdbool.h>

typedef struct {
    bool valid;
    bool lightSurface;
    double luminance;
    double primaryWhite;
    double secondaryWhite;
    double bodyWhite;
    double bodyOpacity;
} GFNotificationPalette;

static inline double GFNotificationLinearChannel(double value) {
    double normalized = (value + 0.055) / 1.055;
    return value <= 0.04045 ? value / 12.92 : pow(normalized, 2.4);
}

static inline GFNotificationPalette GFNotificationPaletteForAppearance(bool light) {
    GFNotificationPalette result = {
        true, light, -1.0, light ? 0.07 : 0.98, light ? 0.37 : 0.78,
        light ? 0.90 : 0.0, light ? 0.18 : 0.035
    };
    return result;
}

static inline GFNotificationPalette GFNotificationPaletteForWallpaper(
    double red, double green, double blue, double alpha,
    bool hasPrevious, bool previousLight
) {
    GFNotificationPalette invalid = {false, false, -1.0, 0, 0, 0, 0};
    if (!isfinite(red) || !isfinite(green) || !isfinite(blue) || !isfinite(alpha) ||
        red < 0 || red > 1 || green < 0 || green > 1 || blue < 0 || blue > 1 ||
        alpha < 0.95 || alpha > 1.0) return invalid;
    double luminance = 0.2126 * GFNotificationLinearChannel(red) +
                       0.7152 * GFNotificationLinearChannel(green) +
                       0.0722 * GFNotificationLinearChannel(blue);
    double threshold = hasPrevious ? (previousLight ? 0.16 : 0.185) : 0.18;
    GFNotificationPalette result = GFNotificationPaletteForAppearance(luminance >= threshold);
    result.luminance = luminance;
    result.secondaryWhite = result.lightSurface ? 0.07 + 0.30 * luminance :
        0.82 + 0.16 * fmin(1.0, luminance / 0.185);
    if (result.lightSurface) {
        // Preserve a white lift while there is headroom; near white, a small
        // neutral absorption keeps the surface distinguishable without a slab.
        double highlight = fmax(0.0, fmin(1.0, (luminance - 0.85) / 0.15));
        highlight = highlight * highlight * (3.0 - 2.0 * highlight);
        result.bodyWhite = 1.0 - 0.22 * highlight;
    }
    return result;
}
#endif
