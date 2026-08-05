/*
--------------------------------------------------------------------------------

    Revelation Shaders (Ultra Performance Edition - UnderWater Pass Disabled)

    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Underwater volumetric fog (DISABLED – replaced by analytic fog elsewhere)
    Optimization: RaymarchWaterFog removed, temporal reprojection skipped.
--------------------------------------------------------------------------------
*/

#define PASS_VOLUMETRIC_FOG

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 11 */
out uvec4 packedFogData;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

// 不再需要 water fog 步进，只保留空的编码输出
// #include "/lib/water/WaterFog.glsl"

mat2x3 UnpackFogData(in uvec2 data) {
    return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
}

//======// Main //================================================================================//
void main() {
    // 玩家不在水中 → 直接输出完全透明的雾，并立即返回
    if (isEyeInWater == 0) {
        packedFogData = uvec4(EncodeRGBE8U(vec3(0.0)), EncodeRGBE8U(vec3(1.0)), 0u, 0u);
        return;
    }

    // 即使在水下，也不再执行任何体积步进，直接输出无散射的雾数据。
    // 雾效将由 AnalyticWaterFog 在其它 Pass 中处理。
    packedFogData = uvec4(
        EncodeRGBE8U(vec3(0.0)), // 散射为零
        EncodeRGBE8U(vec3(1.0)), // 透射率为 1（完全透明）
        0u,                      // 不需要深度信息
        0u
    );
}