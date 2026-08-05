/*
--------------------------------------------------------------------------------

    Revelation Shaders

    Copyright (C) 2026 HaringPro
    Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out uint normalPack;
flat out uvec2 tangentPack;

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 worldPos;

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelViewInverse;
uniform vec2 taaJitter;

//======// Function //============================================================================//

#define PHYSICS_OCEAN_SUPPORT
#ifdef PHYSICS_OCEAN
    #define PHYSICS_VERTEX
    #include "/lib/water/PhysicsOceans.glsl"
#endif

//======// Main //================================================================================//
void main() {
    texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;
    lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

    // Nether portal brightness
    lightmap.x = float(mc_Entity.x == 11500.0);

    vertColor = gl_Color;

    // Encode normal and tangent into packed integers
    vec3 normal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    normalPack = packSnorm2x16(OctEncodeSnorm(normal));

    vec3 tangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
    tangentPack.x = packSnorm2x16(OctEncodeSnorm(tangent));
    // Store the handedness of the tangent space as -1.0 or 1.0
    tangentPack.y = (floatBitsToUint(at_tangent.w) & 0x80000000u) | 0x3F800000u;

    materialID = mc_Entity.x == 10003.0 ? 3u : 2u;

    vec3 viewPos;
    #ifdef PHYSICS_OCEAN
        physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r;
        vec4 finalPosition = vec4(gl_Vertex.x,
                                   gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime),
                                   gl_Vertex.z,
                                   gl_Vertex.w);
        physics_localPosition = finalPosition.xyz;
        viewPos = transMAD(gl_ModelViewMatrix, finalPosition.xyz);
    #else
        viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
    #endif

    worldPos = transMAD(gbufferModelViewInverse, viewPos);

    gl_Position = diagonal4(gl_ProjectionMatrix) * viewPos.xyzz + gl_ProjectionMatrix[3];
    #ifdef TAA_ENABLED
        gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}