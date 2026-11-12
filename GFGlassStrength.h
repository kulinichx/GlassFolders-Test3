#ifndef GF_GLASS_STRENGTH_H
#define GF_GLASS_STRENGTH_H

#include <math.h>

static inline double GFSharedGlassAmount(double amount) {
    return isfinite(amount) ? fmin(1.0, fmax(0.0, amount)) : 0.5;
}

static inline double GFSharedGlassScale(double amount) {
    return 2.0 * GFSharedGlassAmount(amount);
}

#endif
