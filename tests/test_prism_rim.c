#include "../GFPrismRim.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

static void valid_rgba(const unsigned char p[4]) {
    assert(p[0] <= p[3]);
    assert(p[1] <= p[3]);
    assert(p[2] <= p[3]);
}
int main(void) {
    unsigned char p[4];
    GFPrismRimRGBA(p,0.45, 1.0,1.0, 1.0,0.0,1.0);
    valid_rgba(p);
    assert(p[0] != p[2]);
    unsigned char frontR=p[0],frontB=p[2];
    GFPrismRimRGBA(p,0.45, 1.0,1.0, -1.0,0.0,1.0);
    valid_rgba(p);
    assert(frontR == p[2] && frontB == p[0]);
    GFPrismRimRGBA(p,1.0, 1.0,1.0, 0.0,0.0,0.0);
    assert(p[0] == 255 && p[1] == 255 && p[2] == 255 && p[3] == 255);
    GFPrismRimRGBA(p,0.0, 1.0,1.0, 1.0,0.0,1.0);
    assert(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0);
    GFPrismRimRGBA(p,0.5, 100.0,1.0,1.0,0.0,1.0);
    assert(p[0] == p[1] && p[1] == p[2]);
    for (int k=0;k<100;k++) {
        double depth=k*0.2;
        GFPrismRimRGBA(p, 0.4,depth,1.5,0.6,0.8,0.9);
        valid_rgba(p);
    }
    // New independent intensity multiplies the existing rim strength.
    GFPrismRimRGBA(p,0.45,1.0,1.0,1.0,0.0,0.0);
    assert(p[0] == p[1] && p[1] == p[2]);
    GFPrismRimRGBA(p,0.45,1.0,1.0,1.0,0.0,0.35);
    assert(p[0] != p[2]);
    GFPrismRimRGBA(p,NAN,1.0,1.0,1.0,0.0,1.0);
    assert(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0);
    assert(GFPrismClamp01(NAN) == 0.0);
    assert(GFPrismClamp01(INFINITY) == 1.0);
    puts("GFPrismRim C tests: PASS");
    return 0;
}
