#include <metal_stdlib>
using namespace metal;

#include "../Sources/ShaderTypes/include/ShaderTypes.h"

struct TextVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex TextVertexOut text_vertex(uint vid [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    float2 uvs[6] = {
        float2(0, 1), float2(1, 1), float2(0, 0),
        float2(0, 0), float2(1, 1), float2(1, 0)
    };
    TextVertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
}

fragment float4 text_fragment(TextVertexOut in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(0)]],
                               texture2d<float> textAtlas [[texture(0)]]) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::repeat);

    // Scroll the texture
    float2 uv = in.uv;
    uv.y = fract(uv.y + uniforms.scrollOffset);

    float4 texColor = textAtlas.sample(texSampler, uv);

    // If alpha is very low, show a dark background
    if (texColor.a < 0.01) {
        return float4(0.05, 0.05, 0.08, 1.0);
    }

    return float4(texColor.rgb, 1.0);
}
