// Optics Lab 05: dynamic SYNTHETIC test input, not SpringBoard capture.
#include <metal_stdlib>
using namespace metal;
struct GFProbeVertex { float4 position [[position]]; float2 uv; };
struct GFProbeBackgroundParams { float2 sizePx; float timeSec; float reserved; };
struct GFProbePanelParams { float2 screenSizePx; float2 originPx; float2 panelSizePx; float opacity; float reserved; };
vertex GFProbeVertex gfProbeVertex(uint id [[vertex_id]]) {
    float2 uv = float2((id << 1) & 2, id & 2);
    GFProbeVertex v;
    v.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    v.uv = uv;
    return v;
}
constexpr sampler gfLinearSampler(min_filter::linear,mag_filter::linear,address::clamp_to_edge);
fragment float4 gfProbeBackground(GFProbeVertex v [[stage_in]],
                                  constant GFProbeBackgroundParams &s [[buffer(0)]]) {
    float2 p = v.uv * s.sizePx;
    // The bright moving lines make non-zero displacement visually measurable.
    float shift = sin(s.timeSec * 0.8) * 28.0;
    float2 grid = abs(fract((p + float2(shift, 0.0)) / 44.0) - 0.5);
    float stroke = smoothstep(0.475, 0.495, max(grid.x, grid.y));
    float diagonal = 1.0 - smoothstep(1.0, 3.5,
                         abs(p.x - (0.57 * p.y + 80.0 + shift * 3.0)));
    float wave = 0.15 * sin((p.x+p.y) / 75.0 + s.timeSec * 0.9);
    float3 base = float3(0.12, 0.29, 0.36) + float3(wave * 0.4,wave,wave);
    float3 color = mix(base,float3(0.89,0.95,0.94),stroke * 0.74);
    color = mix(color,float3(1.0,0.48,0.27),diagonal * 0.9);
    return float4(clamp(color,0.0,1.0),1.0);
}
fragment float4 gfProbeCopy(GFProbeVertex v [[stage_in]],
                            texture2d<float> capture [[texture(0)]]) {
    return capture.sample(gfLinearSampler, v.uv);
}
fragment float4 gfProbePanel(GFProbeVertex v [[stage_in]],
                             texture2d<float> panel [[texture(0)]],
                             constant GFProbePanelParams &p [[buffer(0)]]) {
    float2 pos = v.uv * p.screenSizePx;
    float2 local = (pos-p.originPx)/max(p.panelSizePx,float2(1.0));
    if (any(local < 0.0) || any(local > 1.0)) return float4(0.0);
    float4 refracted = panel.sample(gfLinearSampler, local);
    // Add subtle tint ONLY to make the inset boundary readable; RGB is premultiplied.
    float opacity = clamp(p.opacity,0.0,1.0);
    float alpha = refracted.a * opacity;
    float3 color = mix(refracted.rgb, float3(0.70,0.89,0.99)*refracted.a,0.08);
    return float4(color * opacity,alpha);
}
