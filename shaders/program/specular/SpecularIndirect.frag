/*
--------------------------------------------------------------------------------
    Revelation Shaders (Ultra Performance Edition)
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Compute specular reflections
    Optimizations:
      - Fixed LOD depth culling logic conflict.
      - Cached G-buffer material fetch (Saves bandwidth).
      - Removed dead ALU calculations (Unused absolute worldPos).
    Updated: Use geometry normal and materialID for new reflection function.
--------------------------------------------------------------------------------
*/

#define PASS_SPECULAR_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 3 */
out vec4 specularOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"

#include "/lib/surface/BRDF.glsl"
#include "/lib/surface/Reflection.glsl"

//======// Main //================================================================================//
void main() {
    specularOut = vec4(0.0);

    ivec2 texelPos = ivec2(gl_FragCoord.xy);

    // 一次性读取并缓存材质包
    uvec4 materialPack = loadMaterialPack(texelPos);
    Material material = GetMaterialData(Unpack2x8U(materialPack.z));

    if (material.specularMask) {
        vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, loadDepth0(texelPos));
        vec3 viewPos;

        // LOD 深度修正
        #if defined LOD_MOD
            if (screenPos.z > 1.0 - EPS) {
                screenPos.z = loadDepth0Lod(texelPos);
                viewPos = ScreenToViewPosLod(screenPos);
            } else {
                viewPos = ScreenToViewPos(screenPos);
            }
        #else
            viewPos = ScreenToViewPos(screenPos);
        #endif

        // 天空剔除
        if (screenPos.z > 1.0 - EPS) discard;

        // 手部深度矫正
        if (screenPos.z < 0.56) {
            screenPos.z = screenPos.z * rcp(MC_HAND_DEPTH) + (0.5 - 0.5 / MC_HAND_DEPTH);
            viewPos = ScreenToViewPos(screenPos);
        }

        // 计算世界空间视线方向
        vec3 relativeWorldPos = mat3(gbufferModelViewInverse) * viewPos;
        vec3 worldDir = normalize(relativeWorldPos);

        // 获取几何法线（用于稳定反射）和世界法线
        vec3 geoNormal, worldNormal;
        FetchNormalData(texelPos, geoNormal, worldNormal);

        // 获取材质 ID（用于自定义反射白名单）
        uint materialID = materialPack.y;

        // 光照贴图信息
        vec2 lightmap = Unpack2x8U(materialPack.x);
        float dither = BlueNoise(texelPos, frameCounter);

        // 调用新版反射函数（传入 materialID, 几何法线）
        specularOut = CalculateSpecularReflections(material, materialID, geoNormal, screenPos, worldDir, viewPos, lightmap.y, dither);
    }
}