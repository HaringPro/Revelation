/*
--------------------------------------------------------------------------------
    Revelation Shaders - Shadow Module (Ultimate Optimized)
    Optimizations: Hard-shadow fast path, ALU reduction in refractions, 
                   Hoisted Texels, Caustics Early-Out, Progressive SSS.
    Underground optimization: if SHADOW_CULL_UNDERGROUND is defined,
    shadow calculations are skipped when eyeSkylightSmooth < 0.01.
    PCF: Vogel disk precomputed radii & pre-rotated directions (no per-sample sin/cos).
    SSS: Precomputed step base, minor ALU reductions.
--------------------------------------------------------------------------------
*/

// [0 1 2] 0: Hard Shadow (Fastest), 1: PCF (Medium), 2: PCSS (Physical Soft)
#define SHADOW_SOFT_TYPE 1 // [0 1 2]
#define PCF_SOFT_RADIUS 0.2 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0]
#define SHADOW_BIAS_STRENGTH 2.75 // [1.0 1.25 1.5 1.75 2.0 2.25 2.5 2.75 3.0 4.0 5.0 8.0 10.0 20.0]

#define PCSS_SEARCH_SAMPLES 4 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]
#define PCSS_FILTER_SAMPLES 4 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

// 快速 PCF 采样数（仅对 PCF 模式有效，独立于 PCSS）
#define PCF_FAST_SAMPLES 4 // [2 4 6 8 10 12]

// 开关：是否在远景（LOD）区块内渲染屏幕空间接触阴影 (SSS)
#define SSS_LOD_ENABLED

// 地下阴影剔除开关（与 shadow.frag 中的 SHADOW_CULL_UNDERGROUND 宏配合使用）
// 若在 shadow.frag 或编译参数中定义了该宏，此处将自动生效
// #define SHADOW_CULL_UNDERGROUND

//================================================================================================//

#include "Common.glsl"

// 缓存投影矩阵的关键元素，减少重复索引
const float shadowProjInv1y = shadowProjectionInverse[1].y;
const float shadowProjInv2z = shadowProjectionInverse[2].z;

// ---------- 预计算Vogel盘半径序列（假设最大采样数为16，可扩展） ----------
const float vogelRadii[16] = float[16](
    0.176776, 0.306186, 0.395285, 0.467707, 0.530330, 0.586302, 0.637378, 0.684653,
    0.728869, 0.770552, 0.810093, 0.847791, 0.883883, 0.918559, 0.951972, 0.984251
);
const float vogelAngleStep = 2.39996323; // goldenAngle

vec3 WorldToShadowScreenSpace(in vec3 worldPos) {
    vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
    shadowClipPos = projMAD(shadowProjection, shadowClipPos);
    vec3 result = DistortShadowSpace(shadowClipPos) * 0.5 + 0.5;
    // 体素化平铺布局：真阴影被挤到右上区，采样坐标须同步 Shift（shadow GS 发射侧同样 Shift）
    #ifdef ENABLE_VOXELIZATION
        ShiftShadowScreenPos(result.xy);
    #endif
    return result;
}

vec3 WorldToShadowScreenSpace(in vec3 worldPos, out float distortionFactor) {
    vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
    shadowClipPos = projMAD(shadowProjection, shadowClipPos);
    distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
    vec3 result = DistortShadowSpace(shadowClipPos, distortionFactor) * 0.5 + 0.5;
    #ifdef ENABLE_VOXELIZATION
        ShiftShadowScreenPos(result.xy);
    #endif
    return result;
}

//================================================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

// 遮挡物搜索 (PCSS专用)
float BlockerSearch(in vec3 shadowScreenPos, in float dither, in float searchScale) {
    float blockerDepth = 0.0;
    
    #if PCSS_SEARCH_SAMPLES > 0
        vec2 searchRadius = searchScale * diagonal2(shadowProjection);
        vec2 baseTexel = shadowScreenPos.xy * realShadowMapRes;
        vec2 radiusTexel = searchRadius * realShadowMapRes;

        #pragma unroll
        for (uint i = 0u; i < PCSS_SEARCH_SAMPLES; ++i) {
            vec2 sampleTexel = baseTexel + sampleVogelDisk(i, PCSS_SEARCH_SAMPLES, dither) * radiusTexel;
            float sampleDepth = texelFetch(shadowtex0, ivec2(sampleTexel), 0).x;
            blockerDepth += saturate(shadowScreenPos.z - sampleDepth);
        }
        blockerDepth *= -5.0 / float(PCSS_SEARCH_SAMPLES);
        return blockerDepth * shadowProjInv2z;
    #else
        return 0.0;
    #endif
}

// 水底焦散计算（增强版：光斑更大，亮度翻倍）
vec3 CalculateWaterCaustics(in vec3 worldPos, in float waterDepth, in float dither) {
    vec3 surfacePos = worldPos - vec3(0.0, 1.0, 0.0);
    float caustics = 0.0;

    #pragma unroll
    for (uint i = 0u; i < 4u; ++i) {
        vec3 samplePos = worldPos;
        samplePos.xz += sampleVogelDisk(i, 4, dither) * 0.15;

        vec2 sampleCoord = WorldToShadowScreenSpace(samplePos).xy;
        vec3 waveNormal = OctDecodeUnorm(texture(shadowcolor1, sampleCoord).xy);

        vec3 refractDir = refract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_IOR);
        
        // 优化：消除 abs()。因光线朝下，refractDir.y 必为负。
        vec3 refractedPos = samplePos - refractDir / refractDir.y;

        // 减小距离衰减系数（20→12）使焦散光斑更大更亮
        caustics += saturate(1.0 - 12.0 * distance(surfacePos, refractedPos));
    }
    // 亮度增强 2 倍，让焦散在昏暗水底更明显
    const float brightnessBoost = 2.0;
    return brightnessBoost * (-smin(-caustics, -0.1, 0.15)) * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}

// 核心采样过滤 (PCF/PCSS/Hard)
vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in vec3 worldPos, in float dither, in float blockerDepth) {
    
    #if SHADOW_SOFT_TYPE == 0
        // ---- 模式 0：硬阴影 (Fastest) 单次采样快速通道 ----
        float sampleDepth1 = textureLod(shadowtex1, vec3(shadowScreenPos.xy, shadowScreenPos.z), 0).x;

        #ifdef COLORED_SHADOWS
            ivec2 sampleTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
            float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;

            if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
                float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
                if (waterMask > EPS) {
                    float waterDepth = (sampleDepth0 - shadowScreenPos.z) * shadowProjInv2z * 5.0;
                    return CalculateWaterCaustics(worldPos, waterDepth, dither);
                } else {
                    vec3 col = texelFetch(shadowcolor0, sampleTexel, 0).rgb;
                    return (col * col * col) * sampleDepth1; // cube()
                }
            }
        #endif

        return vec3(sampleDepth1);

    #elif SHADOW_SOFT_TYPE == 1
        // ---- 模式 1：快速 PCF 模式（优化版，预计算偏移） ----
        const uint pcfSamples = PCF_FAST_SAMPLES;
        const float rSteps = 1.0 / float(pcfSamples);
        vec2 penumbraRadius = PCF_SOFT_RADIUS * diagonal2(shadowProjection);

        float invRes = realShadowMapRes;
        vec2 baseSampleCoord = shadowScreenPos.xy;

        // 随机旋转全部采样方向
        float angleOffset = goldenAngle * dither;
        float cosRot = cos(angleOffset);
        float sinRot = sin(angleOffset);

        vec3 result = vec3(0.0);
        vec2 waterData = vec2(0.0);

        #pragma unroll
        for (uint i = 0u; i < pcfSamples; ++i) {
            // 预计算基础方向
            float angle = vogelAngleStep * float(i);
            vec2 dir = vec2(cos(angle), sin(angle));
            // 应用随机旋转
            dir = vec2(cosRot * dir.x - sinRot * dir.y, sinRot * dir.x + cosRot * dir.y);
            // 半径取自预计算表
            vec2 offset = dir * (vogelRadii[i] * penumbraRadius);

            vec2 sampleCoord = baseSampleCoord + offset;
            float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

            #ifdef COLORED_SHADOWS
                ivec2 sampleTexel = ivec2(sampleCoord * invRes);
                float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;

                if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
                    float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
                    if (waterMask > EPS) {
                        waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
                    } else {
                        vec3 col = texelFetch(shadowcolor0, sampleTexel, 0).rgb;
                        result += (col * col * col) * sampleDepth1;
                    }
                } else
            #endif
                result += sampleDepth1;
        }

        result *= rSteps;

        #ifdef WATER_CAUSTICS
            if (waterData.y > EPS) {
                waterData.x /= waterData.y;
                float waterDepth = waterData.x * shadowProjInv2z * 5.0;
                vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
                result = mix(result, caustics, waterData.y * rSteps);
            }
        #endif

        return result;

    #else
        // ---- 模式 2：物理 PCSS 模式（保持不变，使用原 sampleVogelDisk） ----
        const float rSteps = 1.0 / float(PCSS_FILTER_SAMPLES);
        vec2 penumbraRadius = min(sunAngularRadius * 2.0 * blockerDepth, 0.25) * diagonal2(shadowProjection);

        float invRes = realShadowMapRes;
        vec2 baseSampleCoord = shadowScreenPos.xy;

        vec3 result = vec3(0.0);
        vec2 waterData = vec2(0.0);

        #pragma unroll
        for (uint i = 0u; i < PCSS_FILTER_SAMPLES; ++i) {
            vec2 offset = sampleVogelDisk(i, PCSS_FILTER_SAMPLES, dither) * penumbraRadius;
            vec2 sampleCoord = baseSampleCoord + offset;
            float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

            #ifdef COLORED_SHADOWS
                ivec2 sampleTexel = ivec2(sampleCoord * invRes);
                float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;

                if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
                    float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
                    if (waterMask > EPS) {
                        waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
                    } else {
                        vec3 col = texelFetch(shadowcolor0, sampleTexel, 0).rgb;
                        result += (col * col * col) * sampleDepth1;
                    }
                } else
            #endif
                result += sampleDepth1;
        }

        result *= rSteps;

        #ifdef WATER_CAUSTICS
            if (waterData.y > EPS) {
                waterData.x /= waterData.y;
                float waterDepth = waterData.x * shadowProjInv2z * 5.0;
                vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
                result = mix(result, caustics, waterData.y * rSteps);
            }
        #endif

        return result;
    #endif
}

// 对外接口：计算PCSS/阴影
vec3 CalculatePCSS(in vec3 worldPos, in vec3 normalOffset, in float dither, out float blockerDepth) {
    // 地下完全跳过阴影计算
    #ifdef SHADOW_CULL_UNDERGROUND
        if (eyeSkylightSmooth < 0.01) {
            blockerDepth = 0.0;
            return vec3(1.0);
        }
    #endif

    blockerDepth = 0.0;
    float distortionFactor;
    
    vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset * SHADOW_BIAS_STRENGTH, distortionFactor);
    shadowScreenPos.z -= 3e-8 * (1.0 + dither) * shadowProjInv1y * distortionFactor * SHADOW_BIAS_STRENGTH;

    vec3 shadowResult = vec3(1.0);
    
    if (saturate(shadowScreenPos) == shadowScreenPos) {
        #if SHADOW_SOFT_TYPE == 2
            blockerDepth = BlockerSearch(shadowScreenPos, dither * TAU, 0.15 * distortionFactor);
            const float minRadius = 0.008 / sunAngularRadius;
            float sharpenFactor = saturate(blockerDepth * rcp(minRadius));

            shadowResult = PercentageCloserFilter(shadowScreenPos, worldPos, dither * TAU, max(blockerDepth, minRadius) * distortionFactor);
            shadowResult = mix(smoothstep(0.3, 0.7, shadowResult), shadowResult, sharpenFactor);
        #else
            shadowResult = PercentageCloserFilter(shadowScreenPos, worldPos, dither * TAU, 0.0);
        #endif
    }

    return shadowResult;
}

// 屏幕空间接触阴影 (SSS)
float ScreenSpaceShadow(in vec3 rayPos, in vec3 viewPos, in float dither, in float sssAmount) {
    // 地下完全跳过 SSS 计算
    #ifdef SHADOW_CULL_UNDERGROUND
        if (eyeSkylightSmooth < 0.01) return 1.0;
    #endif

    #if defined LOD_MOD
        #ifndef SSS_LOD_ENABLED
            if (rayPos.z > 1.0 - EPS) return 1.0;
        #endif
    #endif

    vec3 rayDir = ViewToScreenPos(viewLightDir * abs(viewPos.z) + viewPos) - rayPos;
    rayDir *= minOf((step(0.0, rayDir) - rayPos) / rayDir);
    rayDir *= inversesqrt(sdot(rayDir.xy));

    // 编译期常量折叠
    const float sssStepBase = 0.035 / float(SCREEN_SPACE_SHADOWS_SAMPLES);
    vec3 rayStep = rayDir * sssStepBase;
    rayPos += (dither + 0.5) * rayStep;

    float viewDistInv = inversesqrt(sdot(viewPos));
    float diffTolerance = 5e-4 * viewDistInv;
    float absorption = exp2(-0.125 / (viewDistInv * sssAmount));

    float result = 1.0;
    
    for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i) {
        if (saturate(rayPos.xy) != rayPos.xy || result < 1e-2) break;

        ivec2 sampleTexel = uvToTexel(rayPos.xy);
        float sampleDepth = loadDepth0(sampleTexel);
        bool hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;

        #if defined LOD_MOD && defined SSS_LOD_ENABLED
            if (sampleDepth > 1.0 - EPS) {
                sampleDepth = loadDepth0Lod(sampleTexel);
                sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(sampleDepth));
                hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
            }
        #endif

        result *= saturate(absorption + 1.0 - float(hit));
        rayStep *= 1.08;
        rayPos += rayStep;
    }
    return result;
}