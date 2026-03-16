#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef struct {
    float time;
    float scrollOffset;
    simd_float2 resolution;
} Uniforms;

typedef struct {
    simd_float2 position;
    simd_float2 texCoord;
    simd_float4 color;
} VertexIn;

typedef struct {
    simd_float2 position;
    simd_float2 velocity;
    simd_float4 color;
    float size;
    float _padding[3];
} ParticleData;

#endif
