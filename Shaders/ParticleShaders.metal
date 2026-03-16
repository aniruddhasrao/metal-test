#include <metal_stdlib>
using namespace metal;

#include "../Sources/ShaderTypes/include/ShaderTypes.h"

struct ParticleVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex ParticleVertexOut particle_vertex(uint vid [[vertex_id]],
                                          uint iid [[instance_id]],
                                          constant ParticleData *particles [[buffer(0)]],
                                          constant Uniforms &uniforms [[buffer(1)]]) {
    ParticleData p = particles[iid];

    // 6 vertices per quad (2 triangles)
    float2 offsets[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };

    float2 offset = offsets[vid] * p.size / uniforms.resolution;
    float2 ndcPos = (p.position / uniforms.resolution) * 2.0 - 1.0;
    ndcPos.y = -ndcPos.y; // flip Y for Metal NDC

    ParticleVertexOut out;
    out.position = float4(ndcPos + offset, 0, 1);
    out.color = p.color;
    out.pointSize = p.size;
    return out;
}

fragment float4 particle_fragment(ParticleVertexOut in [[stage_in]]) {
    return in.color;
}

// Compute kernel to update particle positions
kernel void particle_update(device ParticleData *particles [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             constant uint &particleCount [[buffer(2)]],
                             uint id [[thread_position_in_grid]]) {
    if (id >= particleCount) return;

    ParticleData p = particles[id];

    float dt = 1.0 / 60.0;

    // Apply gravity
    p.velocity.y += 150.0 * dt;

    // Update position
    p.position += p.velocity * dt;

    // Bounce off walls
    float2 res = uniforms.resolution;
    if (p.position.x < 0.0) { p.position.x = 0.0; p.velocity.x *= -0.8; }
    if (p.position.x > res.x) { p.position.x = res.x; p.velocity.x *= -0.8; }
    if (p.position.y < 0.0) { p.position.y = 0.0; p.velocity.y *= -0.8; }
    if (p.position.y > res.y) {
        p.position.y = res.y;
        p.velocity.y *= -0.8;
        // Give a little random kick so they don't settle
        float hash = fract(sin(float(id) * 12.9898 + uniforms.time) * 43758.5453);
        if (hash > 0.7) {
            p.velocity.y -= 200.0 * hash;
            p.velocity.x += (hash - 0.5) * 100.0;
        }
    }

    // Slowly fade color cycling
    float phase = uniforms.time * 0.5 + float(id) * 0.01;
    p.color = float4(
        0.5 + 0.5 * sin(phase),
        0.5 + 0.5 * sin(phase + 2.094),
        0.5 + 0.5 * sin(phase + 4.189),
        0.85
    );

    particles[id] = p;
}
