#ifndef GF_NOTIFICATION_BLUR_H
#define GF_NOTIFICATION_BLUR_H

#include <math.h>

// The midpoint keeps each scene's recipe; the slider changes blur only.
static inline double GFNotificationBlurScale(double amount) {
    if (!isfinite(amount)) amount = 0.5;
    return 2.0 * fmin(1.0, fmax(0.0, amount));
}

#endif
