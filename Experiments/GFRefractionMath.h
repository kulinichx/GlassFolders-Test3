#ifndef GF_REFRACTION_MATH_H
#define GF_REFRACTION_MATH_H

/* Portable scalar reference implementation for Optics Lab 04.
 * Coordinates are PIXELS, with a top-left origin and pixel centers at +0.5.
 * This is an offline mapping reference, not a compositor/capture hook.
 * Implementation intentionally mirrors Experiments/GFRefraction.metal.
 */

typedef struct {
    float captureWidthPx;
    float captureHeightPx;
    float originXPx;
    float originYPx;
    float panelWidthPx;
    float panelHeightPx;
    float cornerRadiusPx;
    float bevelWidthPx;
    float maxOffsetPx;
    float dispersionPx;
} GFRefractionGeometry;

typedef struct {
    float rUV[2];
    float gUV[2];
    float bUV[2];
    float coverage;
    float displacementPx[2];
    float chromaDisplacementPx[2];
} GFRefractionMapping;

/* Returns 1 for validated geometry, 0 for invalid input. Outside the rounded
 * panel, coverage is zero and the UVs are still initialized. A valid result
 * does NOT imply that a texture capture or renderer is available. */
int GFRefractionMapPixel(const GFRefractionGeometry *g,
                         float localXPx, float localYPx,
                         GFRefractionMapping *out);

#endif
