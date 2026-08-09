//#version 430 compatibility
/*
--------------------------------------------------------------------------------

    Revelation Shaders

    Copyright (C) 2026 HaringPro
    Apache License 2.0
    
    Feature: Voxel Mapping Integration

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define WAVING_FOLIAGE
#define WAVING_FOLIAGE_SPEED 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
#define WAVING_FOLIAGE_STRENGTH 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3 0.33 0.36 0.4 0.43 0.46 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define UNLABELLED_FOILAGE_DETECTION

// === Voxel Settings ===
#define VOXEL_AREA 64      // [32 64 128]
#ifndef VOXEL_RADIUS
    #define VOXEL_RADIUS (VOXEL_AREA/2)
#endif

//======// Output //==============================================================================//

flat out uint normalPack;
#if defined MC_NORMAL_MAP
flat out uvec2 tangentPack;
#endif

out vec3 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
    out vec2 tileBase;
    flat out vec2 tileScale;
    flat out vec2 tileOffset;
#endif

// --- Voxel Outputs ---
out vec3 block_centered_relative_pos; // 仅 DEBUG_VOXEL 可视化读取用；体素化已迁到 shadow pass

//======// Attribute & Uniform //=================================================================//

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;
in vec4 at_midBlock;

uniform sampler2D tex; 

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

//======// Main //================================================================================//
void main() {
    vertColor = gl_Color.rgb;
    texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

    lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

    vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(gl_ModelViewMatrix, gl_Vertex.xyz));

    materialID = uint(max(mc_Entity.x - 1e4, 1));

    // Encode normal and tangent
    vec3 normal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    normalPack = packSnorm2x16(OctEncodeSnorm(normal));
    #if defined MC_NORMAL_MAP
        vec3 tangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
        tangentPack.x = packSnorm2x16(OctEncodeSnorm(tangent));
        tangentPack.y = (floatBitsToUint(at_tangent.w) & 0x80000000u) | 0x3F800000u;
    #endif

    // --- Voxel 可视化坐标（世界对齐网格 + cameraPositionFract，照抄 参考实现）---
    // 注意：此处 worldPos 是相机相对坐标（gbufferModelViewInverse 不包含相机平移，
    // 证据见下方枝叶摇曳代码：要先 worldPos += cameraPosition 才是绝对坐标）。
    // 参考实现 世界对齐网格：体素坐标 = 相机相对 + cameraPositionFract（小数对齐，网格
    // 在绝对世界上固定，相机仅移动整数格时网格内容整体平移，由重投影补偿）+
    // voxelResolution * 0.5。shadow pass 的体素化（Shadow.vert）用同一公式。
    vec3 voxelCenterPos = worldPos + cameraPositionFract + float(VOXEL_RADIUS);
    block_centered_relative_pos = voxelCenterPos;
    // --------------------------------------------------------------------------------

    #ifdef WAVING_FOLIAGE
        // Plants
        if (clamp(materialID, 1000u, 1002u) == materialID) {
            worldPos += cameraPosition;

            float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
            float intensity = cube(lightmap.y) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;
            float topVertex = step(gl_MultiTexCoord0.y, mc_midTexCoord.y) + float(materialID == 1001u);
            intensity *= step(materialID, 1000u) * 0.25 + 0.75; // Decrease intensity for tall plants

            float noise = textureBicubic(noisetex, (worldPos.xz + time) * 0.005).x * 2.0;

            float windOffset = sin(dot(worldPos.xz, vec2(2.0, 2.5)) + sin(time * 0.5) * 2.0);
            windOffset *= sin(dot(worldPos.xz + time * 2.0, vec2(1.0, 0.75))) + noise;
            worldPos.xz += vec2(0.4, 0.3) * windOffset * intensity * topVertex;

            worldPos -= cameraPosition;
        }

        // Leaves
        if (materialID == 13u) {
            worldPos += cameraPosition;

            float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
            float intensity = cube(lightmap.y) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;

            float noise = Pseudo3DNoise((worldPos + time) * 2.0) * 2.0;

            float windOffset = sin(dot(worldPos, vec3(2.0, 1.5, 1.5)) + sin(time * 0.5) * 2.0);
            windOffset *= sin(dot(worldPos + time * 2.0, vec3(1.0, 0.5, 0.75))) + noise;
            worldPos += vec3(0.15, 0.1, 0.1) * windOffset * intensity;

            worldPos -= cameraPosition;
        }
    #endif

    // Unlabelled foilage detection
    #ifdef UNLABELLED_FOILAGE_DETECTION
        if (materialID < 1u && maxOf(abs(gl_Normal)) < 0.99) materialID = 1003u;
    #endif

    #if defined PARALLAX || defined AUTO_GENERATED_NORMAL
        vec2 minMidCoord = texCoord - mc_midTexCoord;
        tileBase = signI(minMidCoord) * 0.5 + 0.5;
        tileScale = abs(minMidCoord) * 2.0;
        tileOffset = min(texCoord, mc_midTexCoord - minMidCoord);
    #endif

    gl_Position = diagonal4(gl_ProjectionMatrix) * transMAD(gbufferModelView, worldPos).xyzz + gl_ProjectionMatrix[3];

    #ifdef TAA_ENABLED
        gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}