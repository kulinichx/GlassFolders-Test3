#ifndef GF_NOTIFICATION_CONTRAST_H
#define GF_NOTIFICATION_CONTRAST_H

#include <math.h>
#include <stdbool.h>

// A foreground-aware safety bound, not a measurement of wallpaper brightness.
// Keep the original material if readability would require an almost opaque veil.
static const double GFNotificationMinimumContrast = 4.5;
static const double GFNotificationMaximumVeilOpacity = 0.72;

typedef struct {
    double darkOpacity;
    double lightOpacity;
    unsigned int samples;
    bool valid;
} GFNotificationContrastAccumulator;

typedef struct {
    double opacity;
    bool lightSurface;
    bool valid;
} GFNotificationContrastResult;

static inline double GFNotificationLinearChannel(double channel) {
    if (channel <= 0.04045) return channel / 12.92;
    double normalized = (channel + 0.055) / 1.055;
    return pow(normalized, 2.4);
}

static inline double GFNotificationEncodedChannel(double channel) {
    return channel <= 0.0031308 ? 12.92 * channel :
        1.055 * pow(channel, 1.0 / 2.4) - 0.055;
}

static inline double GFNotificationLuminance(double red, double green, double blue) {
    double linearRed = GFNotificationLinearChannel(red);
    double linearGreen = GFNotificationLinearChannel(green);
    double linearBlue = GFNotificationLinearChannel(blue);
    return 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue;
}

static inline GFNotificationContrastAccumulator GFNotificationContrastBegin(void) {
    GFNotificationContrastAccumulator result = {0.0, 0.0, 0, true};
    return result;
}

static inline void GFNotificationContrastAdd(GFNotificationContrastAccumulator *state,
                                              double red, double green, double blue,
                                              double alpha) {
    if (!state || !state->valid) return;
    if (!isfinite(red) || !isfinite(green) || !isfinite(blue) || !isfinite(alpha) ||
        red < 0.0 || red > 1.0 || green < 0.0 || green > 1.0 ||
        blue < 0.0 || blue > 1.0 || alpha <= 0.0 || alpha > 1.0) {
        state->valid = false;
        return;
    }

    // Bound all RGB backdrops, including colored content, rather than assuming
    // a gray wallpaper. Include the foreground's own translucency in the bound.
    double darkestForeground = GFNotificationLuminance(red * alpha, green * alpha,
                                                       blue * alpha);
    double lightestForeground = GFNotificationLuminance(red * alpha + 1.0 - alpha,
                                                        green * alpha + 1.0 - alpha,
                                                        blue * alpha + 1.0 - alpha);
    double maximumDarkBackground = (darkestForeground + 0.05) /
                                   GFNotificationMinimumContrast - 0.05;
    double minimumLightBackground = GFNotificationMinimumContrast *
                                    (lightestForeground + 0.05) - 0.05;
    double dark = maximumDarkBackground < 0.0 ? INFINITY :
        1.0 - GFNotificationEncodedChannel(fmin(1.0, maximumDarkBackground));
    double light = minimumLightBackground > 1.0 ? INFINITY :
        GFNotificationEncodedChannel(fmax(0.0, minimumLightBackground));
    // A display-code margin protects the numerical bound from alpha rounding.
    state->darkOpacity = fmax(state->darkOpacity, dark + 1.0 / 255.0);
    state->lightOpacity = fmax(state->lightOpacity, light + 1.0 / 255.0);
    state->samples++;
}

static inline GFNotificationContrastResult
GFNotificationContrastResolve(GFNotificationContrastAccumulator state) {
    GFNotificationContrastResult result = {0.0, false, false};
    if (!state.valid || !state.samples) return result;
    result.lightSurface = state.lightOpacity < state.darkOpacity;
    result.opacity = result.lightSurface ? state.lightOpacity : state.darkOpacity;
    result.valid = isfinite(result.opacity) && result.opacity >= 0.0 &&
                   result.opacity <= GFNotificationMaximumVeilOpacity;
    return result;
}

#endif
