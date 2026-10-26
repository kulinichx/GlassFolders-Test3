// Standalone shader design reference. NOT compiled into GlassFolders.
// Requires a separate, verified live-backdrop provider and matching host.
#include <metal_stdlib>
using namespace metal;

struct GFRefractionSettings {
    float2 captureSizePx;   // incoming background texture dimensions in px
    float2 originPx;        // panel top-left position in capture coordinates
    float2 panelSizePx;     // rounded panel size in px
    float cornerRadiusPx;
    float maxOffsetPx;      // e.g. 1.0 to 3.0 (not validated on device)
    float dispersionPx;     // e.g. 0.12 to 0.45
};

struct GFFullScreenVertex {
    float4 position [[position]];
    float2 uv;
};

vertex GFFullScreenVertex gfRefractionVertex(uint id [[vertex_id]]) {
    float2 uv = float2((id << 1) & 2, id & 2);
    GFFullScreenVertex out;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = uv;
    return out;
}

static float gfRoundedSDF(float2 p, float2 size, float radius) {
    float2 h = size * 0.5;
    float2 q = abs(p - h) - (h - radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 gfRefractionFragment(GFFullScreenVertex in [[stage_in]],
                                   texture2d<float> source [[texture(0)]],
                                   constant GFRefractionSettings &s [[buffer(0)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float2 px = in.uv * s.panelSizePx;
    float2 captureUV = (s.originPx + px) / max(s.captureSizePx, 1.0);
    float dist = gfRoundedSDF(px, s.panelSizePx, s.cornerRadiusPx);
    // Center unchanged, offset is confined to the inner ~8 px of the bevel.
    float coverage = saturate((-dist + 0.3) / 0.9);
    float falloff = exp(-pow(max(0.0, -dist) / 4.0, 2.0)) * coverage;
    float dx = gfRoundedSDF(px + float2(0.5, 0.0), s.panelSizePx, s.cornerRadiusPx) -
               gfRoundedSDF(px - float2(0.5, 0.0), s.panelSizePx, s.cornerRadiusPx);
    float dy = gfRoundedSDF(px + float2(0.0, 0.5), s.panelSizePx, s.cornerRadiusPx) -
               gfRoundedSDF(px - float2(0.0, 0.5), s.panelSizePx, s.cornerRadiusPx);
    float2 n = normalize(float2(dx, dy) + float2(1e-6, 1e-6));
    float2 offset = n * s.maxOffsetPx * falloff / max(s.captureSizePx, 1.0);
    float2 split = n * s.dispersionPx * falloff / max(s.captureSizePx, 1.0);
    float r = source.sample(smp, captureUV + offset + split).r;
    float g = source.sample(smp, captureUV + offset).g;
    float b = source.sample(smp, captureUV + offset - split).b;
    return float4(r, g, b, 1.0);
}
