#include <metal_stdlib>
using namespace metal;

#include "../Sources/ShaderTypes/include/ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut scenery_vertex(uint vid [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    float2 uvs[6] = {
        float2(0, 1), float2(1, 1), float2(0, 0),
        float2(0, 0), float2(1, 1), float2(1, 0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
}

// Simple hash for noise
float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fragment float4 scenery_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y; // Flip Y so uv.y=0 is bottom, matching CGContext
    float t = uniforms.time;

    // Sky gradient
    float3 skyTop = float3(0.1, 0.15, 0.4);
    float3 skyBottom = float3(0.5, 0.7, 0.9);
    float3 col = mix(skyBottom, skyTop, uv.y);

    // Sun
    float2 sunPos = float2(0.75, 0.75 + 0.05 * sin(t * 0.3));
    float sunDist = length(uv - sunPos);
    float sun = smoothstep(0.08, 0.05, sunDist);
    float glow = smoothstep(0.3, 0.05, sunDist);
    col += float3(1.0, 0.9, 0.3) * sun;
    col += float3(1.0, 0.7, 0.2) * glow * 0.3;

    // Clouds
    for (int i = 0; i < 3; i++) {
        float cy = 0.7 + float(i) * 0.07;
        float2 cp = float2(uv.x * 3.0 + t * 0.05 * (1.0 + float(i) * 0.5), cy * 2.0);
        float cloud = fbm(cp);
        cloud = smoothstep(0.4, 0.7, cloud);
        col = mix(col, float3(1.0, 1.0, 1.0), cloud * 0.6 * smoothstep(0.5, 0.8, uv.y));
    }

    // Mountains - back layer
    float mountainHeight1 = 0.3 + 0.15 * fbm(float2(uv.x * 2.0 + 1.0, 0.0));
    if (uv.y < mountainHeight1) {
        float3 mtnCol = float3(0.25, 0.2, 0.35);
        col = mix(col, mtnCol, smoothstep(mountainHeight1, mountainHeight1 - 0.01, uv.y));
    }

    // Mountains - front layer
    float mountainHeight2 = 0.2 + 0.12 * fbm(float2(uv.x * 3.0 + 5.0, 0.5));
    if (uv.y < mountainHeight2) {
        float3 mtnCol = float3(0.15, 0.12, 0.2);
        col = mix(col, mtnCol, smoothstep(mountainHeight2, mountainHeight2 - 0.01, uv.y));
    }

    // Ground
    float groundLevel = 0.15 + 0.03 * sin(uv.x * 8.0 + 2.0);
    if (uv.y < groundLevel) {
        float3 groundCol = float3(0.15, 0.4, 0.12);
        float grassNoise = noise(uv * 50.0);
        groundCol += float3(0.0, 0.1, 0.0) * grassNoise;
        col = groundCol;
    }

    // Trees
    for (int i = 0; i < 8; i++) {
        float tx = 0.05 + float(i) * 0.125;
        float treeBase = 0.15 + 0.03 * sin(tx * 8.0 + 2.0);

        // Trunk
        float trunkW = 0.008;
        float trunkH = 0.06 + 0.02 * hash(float2(float(i), 0.0));
        if (abs(uv.x - tx) < trunkW && uv.y > treeBase && uv.y < treeBase + trunkH) {
            col = float3(0.35, 0.2, 0.1);
        }

        // Canopy (triangle)
        float canopyBase = treeBase + trunkH;
        float canopyH = 0.08 + 0.03 * hash(float2(float(i), 1.0));
        float canopyW = 0.04 + 0.02 * hash(float2(float(i), 2.0));
        float progress = (uv.y - canopyBase) / canopyH;
        if (uv.y > canopyBase && uv.y < canopyBase + canopyH) {
            float halfW = canopyW * (1.0 - progress);
            if (abs(uv.x - tx) < halfW) {
                float shade = 0.7 + 0.3 * progress;
                col = float3(0.1, 0.45 * shade, 0.08);
            }
        }
    }

    // Water at very bottom
    if (uv.y < 0.06) {
        float wave = sin(uv.x * 30.0 + t * 2.0) * 0.003;
        float waterLine = 0.06 + wave;
        if (uv.y < waterLine) {
            float3 waterCol = float3(0.1, 0.3, 0.6);
            float sparkle = pow(max(0.0, sin(uv.x * 60.0 + t * 3.0)), 20.0) * 0.5;
            waterCol += float3(sparkle);
            col = waterCol;
        }
    }

    return float4(col, 1.0);
}
