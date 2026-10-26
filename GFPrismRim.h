// iOS 16 Optics Lab — subtle chromatic highlights; not live refraction.
// Implemented independently of Mango and safe to compile as plain C.
#ifndef GF_PRISM_RIM_H
#define GF_PRISM_RIM_H

#include <math.h>
#include <stdint.h>

static inline double GFPrismClamp01(double v) {
    // Treat NaN as zero; avoid undefined float-to-integer conversions.
    if (!(v >= 0.0)) return 0.0;
    return v >= 1.0 ? 1.0 : v;
}

// Calculates premultiplied RGBA for a WHITE specular pixel. A pair of small,
// opposing radial fringes approximate spectral separation at the bevel.
// Must not be described as a physical background displacement: this operates
// on an existing highlight texture only, never samples the wallpaper.
static inline void GFPrismRimRGBA(unsigned char out[4],
                                  double alpha, double depthPx,
                                  double scale, double nx, double ny,
                                  double strength) {
    const double a = GFPrismClamp01(alpha);
    const double d = fmax(0.0, depthPx) / fmax(0.01, scale);
    const double energy = GFPrismClamp01(strength);
    const double outer = exp(-pow((d - 0.80) / 0.55, 2.0));
    const double inner = exp(-pow((d - 2.00) / 0.80, 2.0));
    // A signed edge orientation varies the R/B ordering with surface normal.
    const double polarity = fmax(-1.0, fmin(1.0, 0.60 * nx + 0.40 * ny));
    const double dispersion = 0.14 * energy * polarity * (outer - inner);
    const double r = a * (1.0 - fmax(0.0, -dispersion));
    const double g = a * (1.0 - 0.17 * fabs(dispersion));
    const double b = a * (1.0 - fmax(0.0, dispersion));
    // All channels <= alpha, as required by premultiplied RGBA.
    out[0] = (uint8_t)lrint(255.0 * GFPrismClamp01(r));
    out[1] = (uint8_t)lrint(255.0 * GFPrismClamp01(g));
    out[2] = (uint8_t)lrint(255.0 * GFPrismClamp01(b));
    out[3] = (uint8_t)lrint(255.0 * a);
}

#endif // GF_PRISM_RIM_H
