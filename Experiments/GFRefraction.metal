// Optics Lab 04 — independent, genuine TEXTURE displacement.
// THIS DOES NOT CAPTURE a SpringBoard backdrop. The host must supply a fresh
// composited background MTLTexture (top-left origin) AND an offscreen target.
// Opt-in sample renderer below is not included by GlassFolders' Makefile.
// Scalar-equivalent implementation: GFRefractionMath.c.
#include <metal_stdlib>
using namespace metal;

struct GFRefractionUniforms {
    float2 captureSizePx;  // source MTLTexture pixel dimensions
    float2 originPx;       // panel top-left relative to source pixel 0,0
    float2 panelSizePx;    // target MTLTexture pixel dimensions
    float cornerRadiusPx;
    float bevelWidthPx;    // >= 1.0 px; recommended 8-14px
    float maxOffsetPx;     // >=0, <=32; e.g. 5 px
    float dispersionPx;    // >=0, <=8; e.g. 0.45 px
};
struct GFScreenVertex { float4 position [[position]]; float2 uv; };

vertex GFScreenVertex gfRefractionVertex(uint id [[vertex_id]]) {
    // Fullscreen triangle, top-left UV origin; no vertex buffers.
    float2 uv = float2((id << 1) & 2, id & 2);
    GFScreenVertex out;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = uv;
    return out;
}
static float gfSDF(float2 p, float2 size, float radius) {
    float2 halfSize = 0.5 * size;
    float2 q = abs(p - halfSize) - (halfSize - radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}
static float gfSmooth01(float x) {
    x = clamp(x, 0.0, 1.0);
    return x*x*(3.0-2.0*x);
}
fragment float4 gfRefractionFragment(GFScreenVertex in [[stage_in]],
                                    texture2d<float> capture [[texture(0)]],
                                    constant GFRefractionUniforms& s [[buffer(0)]]) {
    constexpr sampler linearSampler(min_filter::linear, mag_filter::linear,
                                    address::clamp_to_edge);
    float2 size = max(s.panelSizePx, float2(1.0));
    float2 pos = in.uv * size;
    float r = clamp(s.cornerRadiusPx, 0.0, min(size.x,size.y)*0.5);
    float dist = gfSDF(pos,size,r);
    float coverage = clamp(0.5-dist,0.0,1.0);
    if (coverage <= 0.0) return float4(0.0);

    float depth = max(0.0,-dist);
    float t = clamp(depth/max(s.bevelWidthPx,1.0),0.0,1.0);
    float envelope = gfSmooth01(depth) * (1.0-t)*(1.0-t);
    float2 grad = float2(gfSDF(pos+float2(0.5,0),size,r)-gfSDF(pos-float2(0.5,0),size,r),
                         gfSDF(pos+float2(0,0.5),size,r)-gfSDF(pos-float2(0,0.5),size,r));
    float nlen = length(grad);
    float2 n = (nlen > 1.0e-5) ? grad/nlen : float2(0);
    float base = clamp(s.maxOffsetPx,0.0,32.0)*envelope;
    float split = clamp(s.dispersionPx,0.0,8.0)*envelope;
    float2 uv = (s.originPx+pos)/max(s.captureSizePx,float2(1.0));
    float2 duv = n/max(s.captureSizePx,float2(1.0));
    float red = capture.sample(linearSampler, clamp(uv+duv*(base+split),0.0,1.0)).r;
    float green = capture.sample(linearSampler, clamp(uv+duv*base,0.0,1.0)).g;
    float blue = capture.sample(linearSampler, clamp(uv+duv*(base-split),0.0,1.0)).b;
    // Output is PREMULTIPLIED for normal alpha compositing.
    return float4(float3(red,green,blue)*coverage, coverage);
}
