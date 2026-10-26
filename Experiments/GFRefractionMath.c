#include "GFRefractionMath.h"
#include <math.h>
#include <string.h>

static float gfClamp(float x, float lo, float hi) {
    return fminf(fmaxf(x, lo), hi);
}
static float gfSDF(float x, float y, float w, float h, float r) {
    const float qx = fabsf(x - w * 0.5f) - (w * 0.5f - r);
    const float qy = fabsf(y - h * 0.5f) - (h * 0.5f - r);
    return hypotf(fmaxf(qx, 0.0f), fmaxf(qy, 0.0f)) +
           fminf(fmaxf(qx, qy), 0.0f) - r;
}
static float gfSmooth01(float x) {
    x = gfClamp(x, 0.0f, 1.0f);
    return x*x*(3.0f - 2.0f*x);
}
static int gfFiniteGeometry(const GFRefractionGeometry *g) {
    if (!g) return 0;
    const float values[] = {
        g->captureWidthPx, g->captureHeightPx,
        g->originXPx, g->originYPx,
        g->panelWidthPx, g->panelHeightPx,
        g->cornerRadiusPx, g->bevelWidthPx,
        g->maxOffsetPx, g->dispersionPx
    };
    for (unsigned i=0; i<sizeof(values)/sizeof(values[0]); ++i)
        if (!isfinite(values[i])) return 0;
    return g->captureWidthPx >= 1.0f && g->captureHeightPx >= 1.0f &&
           g->panelWidthPx >= 1.0f && g->panelHeightPx >= 1.0f &&
           g->cornerRadiusPx >= 0.0f && g->bevelWidthPx >= 1.0f &&
           g->maxOffsetPx >= 0.0f && g->dispersionPx >= 0.0f &&
           g->maxOffsetPx <= 32.0f && g->dispersionPx <= 8.0f;
}

int GFRefractionMapPixel(const GFRefractionGeometry *g,
                         float x, float y, GFRefractionMapping *out) {
    if (!out) return 0;
    memset(out, 0, sizeof(*out));
    if (!gfFiniteGeometry(g) || !isfinite(x) || !isfinite(y)) return 0;
    const float w = g->panelWidthPx, h = g->panelHeightPx;
    const float r = gfClamp(g->cornerRadiusPx, 0.0f, 0.5f*fminf(w, h));
    const float d = gfSDF(x, y, w, h, r);
    // Equivalent to a 1 px wide analytic antialias around d=0.
    out->coverage = gfClamp(0.5f - d, 0.0f, 1.0f);
    const float depth = fmaxf(-d, 0.0f);
    const float t = gfClamp(depth / g->bevelWidthPx, 0.0f, 1.0f);
    const float envelope = gfSmooth01(depth) * (1.0f - t)*(1.0f - t);
    // Distance gradient: outward normal. Avoid division by zero at symmetry.
    const float dx = gfSDF(x+0.5f,y,w,h,r)-gfSDF(x-0.5f,y,w,h,r);
    const float dy = gfSDF(x,y+0.5f,w,h,r)-gfSDF(x,y-0.5f,w,h,r);
    const float len = hypotf(dx, dy);
    const float nx = (len > 1e-5f) ? dx/len : 0.0f;
    const float ny = (len > 1e-5f) ? dy/len : 0.0f;
    const float base = g->maxOffsetPx * envelope;
    const float shift = g->dispersionPx * envelope;
    out->displacementPx[0] = nx*base;
    out->displacementPx[1] = ny*base;
    out->chromaDisplacementPx[0] = nx*shift;
    out->chromaDisplacementPx[1] = ny*shift;
    const float captureX = g->originXPx + x;
    const float captureY = g->originYPx + y;
    const float u0 = captureX/g->captureWidthPx;
    const float v0 = captureY/g->captureHeightPx;
    out->rUV[0] = gfClamp(u0+(nx*(base+shift))/g->captureWidthPx,0,1);
    out->rUV[1] = gfClamp(v0+(ny*(base+shift))/g->captureHeightPx,0,1);
    out->gUV[0] = gfClamp(u0+(nx*base)/g->captureWidthPx,0,1);
    out->gUV[1] = gfClamp(v0+(ny*base)/g->captureHeightPx,0,1);
    out->bUV[0] = gfClamp(u0+(nx*(base-shift))/g->captureWidthPx,0,1);
    out->bUV[1] = gfClamp(v0+(ny*(base-shift))/g->captureHeightPx,0,1);
    return 1;
}
