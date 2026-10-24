#include <metal_stdlib>
using namespace metal;

// Independent GlassFolders shader. The caller supplies a compositor LIVE
// backdrop texture. Never uses a screenshot or tries to access SpringBoard.
struct GFGlassUniforms {
    float4 cardRect;      // screen origin x,y and output/card width,height (px)
    float4 sourceShape;   // source texture width,height; radius; rim width (px)
    float4 optics;        // displacement px; RGB dispersion px; sheen; opacity
    float4 affineAxes;    // screen-to-backdrop map: xx, xy, yx, yy
    float4 affineOffset;  // screen-to-backdrop tx,ty; reserved,reserved
};

static float gfRoundedBoxSDF(float2 p, float2 size, float radius) {
    float2 halfSize = size * 0.5f;
    radius = clamp(radius, 0.0f, min(halfSize.x, halfSize.y));
    float2 q = abs(p - halfSize) - (halfSize - radius);
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - radius;
}

kernel void gfRefractCard(texture2d<float, access::sample> backdrop [[texture(0)]],
                          texture2d<float, access::write> cardOut [[texture(1)]],
                          constant GFGlassUniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cardOut.get_width() || gid.y >= cardOut.get_height()) return;

    float2 local = float2(gid) + 0.5f;
    float2 extent = u.cardRect.zw;
    float radius = u.sourceShape.z;
    float width = max(2.0f, u.sourceShape.w);
    float sd = gfRoundedBoxSDF(local, extent, radius);
    float inside = max(-sd, 0.0f);
    float coverage = smoothstep(0.0f, 1.5f, -sd);
    float rim = 1.0f - smoothstep(1.0f, width, inside);
    float a = coverage * rim * clamp(u.optics.w, 0.0f, 0.94f);
    if (a < 0.002f) { cardOut.write(float4(0.0f), gid); return; }

    // A rounded rectangular surface normal derived from the shape, including
    // curved corners, instead of a hard-coded rectangular gradient.
    float2 grad = float2(
        gfRoundedBoxSDF(local + float2(1,0), extent, radius) -
        gfRoundedBoxSDF(local - float2(1,0), extent, radius),
        gfRoundedBoxSDF(local + float2(0,1), extent, radius) -
        gfRoundedBoxSDF(local - float2(0,1), extent, radius));
    float gl = length(grad);
    float2 n = gl > 1e-4f ? grad / gl : float2(0.0f);
    float displacement = clamp(u.optics.x, 0.0f, 24.0f) * rim * rim;

    float2 screen = u.cardRect.xy + local - displacement * n;
    float2 sampledPx = float2(
        screen.x * u.affineAxes.x + screen.y * u.affineAxes.z + u.affineOffset.x,
        screen.x * u.affineAxes.y + screen.y * u.affineAxes.w + u.affineOffset.y);
    float2 backdropSize = max(u.sourceShape.xy, float2(1.0f));
    float2 uv = sampledPx / backdropSize;
    constexpr sampler sp(coord::normalized, address::clamp_to_edge, filter::linear);
    uv = clamp(uv, float2(0.0f), float2(1.0f));
    float4 base = backdrop.sample(sp, uv);
    float3 rgb = base.rgb;
    float spread = clamp(u.optics.y, 0.0f, 2.0f) * rim;
    if (spread > 0.001f) {
        float2 rotatedN = float2(
            n.x * u.affineAxes.x + n.y * u.affineAxes.z,
            n.x * u.affineAxes.y + n.y * u.affineAxes.w);
        float2 delta = spread * rotatedN / backdropSize;
        rgb.r = backdrop.sample(sp, clamp(uv + delta, 0.0f, 1.0f)).r;
        rgb.b = backdrop.sample(sp, clamp(uv - delta, 0.0f, 1.0f)).b;
    }

    float sheen = clamp(u.optics.z, 0.0f, 0.22f) * pow(rim, 3.0f);
    rgb = clamp(rgb + (1.0f - rgb) * sheen, 0.0f, 1.0f);
    cardOut.write(float4(rgb * a, a), gid); // premultiplied RGBA
}
