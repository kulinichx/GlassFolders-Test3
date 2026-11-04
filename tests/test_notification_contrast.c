#include "../GFNotificationContrast.h"
#include <stdint.h>
#include <stdio.h>

// A failing console test must not open the Windows CRT assertion dialog.
#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        return 1; \
    } \
} while (0)

static double referenceLuminance(const double rgb[3]) {
    double linear[3];
    for (unsigned int i = 0; i < 3; i++) {
        double normalized = (rgb[i] + 0.055) / 1.055;
        linear[i] = rgb[i] <= 0.04045 ? rgb[i] / 12.92 :
            pow(normalized, 2.4);
    }
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

static double renderedContrast(const double fg[4], const double bg[3],
                               GFNotificationContrastResult guard) {
    double surface[3], text[3];
    for (unsigned int i = 0; i < 3; i++) {
        surface[i] = bg[i] * (1.0 - guard.opacity) +
            (guard.lightSurface ? guard.opacity : 0.0);
        text[i] = fg[i] * fg[3] + surface[i] * (1.0 - fg[3]);
    }
    double a = referenceLuminance(surface), b = referenceLuminance(text);
    return (fmax(a, b) + 0.05) / (fmin(a, b) + 0.05);
}

static uint32_t randomState = 128837u;
static double randomChannel(void) {
    randomState = randomState * 1664525u + 1013904223u;
    return (randomState >> 8) / 16777215.0;
}

static GFNotificationContrastResult single(double r, double g, double b, double a) {
    GFNotificationContrastAccumulator state = GFNotificationContrastBegin();
    GFNotificationContrastAdd(&state, r, g, b, a);
    return GFNotificationContrastResolve(state);
}

int main(void) {
    CHECK(fabs(GFNotificationLinearChannel(1.0) - 1.0) < 1e-12);
    CHECK(fabs(GFNotificationLinearChannel(0.5) - 0.21404114048223255) < 1e-12);
    CHECK(fabs(GFNotificationLuminance(1.0, 0.0, 0.0) - 0.2126) < 1e-12);
    CHECK(fabs(GFNotificationEncodedChannel(0.21404114048223255) - 0.5) < 1e-12);
    GFNotificationContrastResult white = single(1, 1, 1, 1);
    GFNotificationContrastResult black = single(0, 0, 0, 1);
    printf("White: valid=%d light=%d opacity=%.9f; black: valid=%d light=%d opacity=%.9f\n",
           (int)white.valid, (int)white.lightSurface, white.opacity,
           (int)black.valid, (int)black.lightSurface, black.opacity);
    if (!white.valid || white.opacity < 0.53 || white.opacity > 0.55) {
        double luminance = GFNotificationLuminance(1.0, 1.0, 1.0);
        double bound = (luminance + 0.05) / GFNotificationMinimumContrast - 0.05;
        double limited = fmin(1.0, bound);
        fprintf(stderr, "Diagnostics: luminance=%.9f bound=%.9f fmin=%.9f encoded=%.9f\n",
                luminance, bound, limited, GFNotificationEncodedChannel(limited));
    }
    CHECK(white.valid && !white.lightSurface && white.opacity > 0.53 && white.opacity < 0.55);
    CHECK(black.valid && black.lightSurface && black.opacity > 0.45 && black.opacity < 0.47);
    CHECK(!GFNotificationContrastResolve(GFNotificationContrastBegin()).valid);
    GFNotificationContrastResult translucentWhite = single(1, 1, 1, 0.8);
    GFNotificationContrastResult translucentBlack = single(0, 0, 0, 0.8);
    CHECK(translucentWhite.valid && translucentWhite.opacity > white.opacity);
    CHECK(translucentBlack.valid && translucentBlack.opacity > black.opacity);
    CHECK(!single(1, 1, 1, 0.5).valid);
    GFNotificationContrastAdd(NULL, 0, 0, 0, 1);

    const double invalid[][4] = {
        {NAN, 0, 0, 1}, {0, INFINITY, 0, 1}, {0, 0, -0.1, 1},
        {1.1, 1, 1, 1}, {0, 0, 0, NAN}, {0, 0, 0, 0}, {0, 0, 0, 1.01}
    };
    for (unsigned int i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++)
        CHECK(!single(invalid[i][0], invalid[i][1], invalid[i][2], invalid[i][3]).valid);

    GFNotificationContrastAccumulator mixed = GFNotificationContrastBegin();
    GFNotificationContrastAdd(&mixed, 1, 1, 1, 1);
    GFNotificationContrastAdd(&mixed, 0, 0, 0, 1);
    CHECK(!GFNotificationContrastResolve(mixed).valid);
    GFNotificationContrastAccumulator invalidThenValid = GFNotificationContrastBegin();
    GFNotificationContrastAdd(&invalidThenValid, NAN, 0, 0, 1);
    GFNotificationContrastAdd(&invalidThenValid, 1, 1, 1, 1);
    CHECK(!GFNotificationContrastResolve(invalidThenValid).valid);

    // Header, body and secondary text must all satisfy the same guard.
    GFNotificationContrastAccumulator palette = GFNotificationContrastBegin();
    GFNotificationContrastAdd(&palette, 1, 1, 1, 1);
    GFNotificationContrastAdd(&palette, 0.8, 0.8, 0.8, 1);
    GFNotificationContrastResult combined = GFNotificationContrastResolve(palette);
    CHECK(combined.valid && !combined.lightSurface && combined.opacity >= white.opacity);
    GFNotificationContrastAccumulator reversed = GFNotificationContrastBegin();
    GFNotificationContrastAdd(&reversed, 0.8, 0.8, 0.8, 1);
    GFNotificationContrastAdd(&reversed, 1, 1, 1, 1);
    CHECK(fabs(GFNotificationContrastResolve(reversed).opacity - combined.opacity) < 1e-12);

    unsigned int accepted = 0, checks = 0;
    for (unsigned int i = 0; i < 40000; i++) {
        double fg[4] = {randomChannel(), randomChannel(), randomChannel(),
                        0.5 + 0.5 * randomChannel()};
        GFNotificationContrastResult guard = single(fg[0], fg[1], fg[2], fg[3]);
        if (!guard.valid) continue;
        accepted++;
        CHECK(isfinite(guard.opacity) && guard.opacity <= GFNotificationMaximumVeilOpacity);
        for (unsigned int j = 0; j < 10; j++) {
            double bg[3] = {randomChannel(), randomChannel(), randomChannel()};
            if (j == 0) bg[0] = bg[1] = bg[2] = 1.0;
            if (j == 1) bg[0] = bg[1] = bg[2] = 0.0;
            CHECK(renderedContrast(fg, bg, guard) >= GFNotificationMinimumContrast - 1e-10);
            checks++;
        }
    }
    CHECK(accepted > 1000);
    printf("Notification sRGB contrast model: %u accepted palettes, %u backdrop checks PASS\n",
           accepted, checks);
    return 0;
}
