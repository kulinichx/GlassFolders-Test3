#include "../Experiments/GFRefractionMath.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static float approximate(float a, float b) { return fabsf(a-b); }

int main(void) {
    GFRefractionGeometry g = {400,300,100,50,120,100,22,12,5,0.7f};
    GFRefractionMapping center,edge,corner,outer,plain,translated;
    assert(GFRefractionMapPixel(&g,60.5f,50.5f,&center));
    assert(center.coverage==1.0f);
    assert(approximate(center.gUV[0],160.5f/400.0f)<1e-6f);
    assert(approximate(center.gUV[1],100.5f/300.0f)<1e-6f);
    assert(approximate(center.rUV[0],center.bUV[0])<1e-6f);

    // The optical region really displaces sampled BACKGROUND pixels.
    assert(GFRefractionMapPixel(&g,60.5f,2.5f,&edge));
    assert(edge.coverage > 0.99f);
    assert(edge.displacementPx[1]<-0.15f);
    assert(edge.gUV[1] < (50+2.5f)/300.0f);
    assert(edge.rUV[1] < edge.gUV[1] && edge.gUV[1] < edge.bUV[1]);
    assert(approximate(edge.rUV[0],edge.gUV[0])<1e-6f);
    // Round corner outside the curve is transparent, even inside its AABB.
    assert(GFRefractionMapPixel(&g,0.5f,0.5f,&corner));
    assert(corner.coverage==0.0f);
    assert(GFRefractionMapPixel(&g,-10.0f,-10.0f,&outer));
    assert(outer.coverage==0.0f);

    // Disabling offset & dispersion produces exactly the identity map.
    g.maxOffsetPx = 0.0f; g.dispersionPx = 0.0f;
    assert(GFRefractionMapPixel(&g,60.5f,2.5f,&plain));
    assert(approximate(plain.rUV[1],(50+2.5f)/300.0f)<1e-6f);
    assert(approximate(plain.gUV[1],plain.bUV[1])<1e-6f);
    // Moving the panel by 40 capture pixels changes UV by 40/captureWidth.
    g.originXPx += 40.0f;
    assert(GFRefractionMapPixel(&g,60.5f,2.5f,&translated));
    assert(approximate(translated.gUV[0]-plain.gUV[0],40.0f/400.0f)<1e-6f);

    // Edge clamping and invalid inputs cannot leak infinities into a sampler.
    g.originXPx = -10000;
    assert(GFRefractionMapPixel(&g,60.5f,2.5f,&outer));
    assert(outer.gUV[0]==0.0f);
    g.originXPx = 100000;
    assert(GFRefractionMapPixel(&g,60.5f,2.5f,&outer));
    assert(outer.gUV[0]==1.0f);
    g.originXPx = 100;
    g.captureWidthPx = 0;
    assert(!GFRefractionMapPixel(&g,60.5f,2.5f,&outer));
    assert(outer.coverage==0.0f);
    g.captureWidthPx = 400;
    g.dispersionPx = NAN;
    assert(!GFRefractionMapPixel(&g,60.5f,2.5f,&outer));
    g.dispersionPx = 0;
    assert(!GFRefractionMapPixel(&g,NAN,5,&outer));
    assert(!GFRefractionMapPixel(&g,10,10,NULL));

    // Numeric stability across radii and very small panels.
    g.panelWidthPx=48; g.panelHeightPx=43; g.cornerRadiusPx=100;
    g.maxOffsetPx=4; g.dispersionPx=0.4f;
    for (int x=0;x<48;++x) for (int y=0;y<43;++y) {
        assert(GFRefractionMapPixel(&g,x+0.5f,y+0.5f,&outer));
        assert(isfinite(outer.coverage) && outer.coverage>=0 && outer.coverage<=1);
        assert(outer.gUV[0]>=0 && outer.gUV[0]<=1);
        assert(outer.gUV[1]>=0 && outer.gUV[1]<=1);
    }
    puts("Optics Lab 04: pixel displacement, RGB sampling, geometry and guards PASS");
    return 0;
}
