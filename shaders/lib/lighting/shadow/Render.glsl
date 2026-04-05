/*
--------------------------------------------------------------------------------
    Revelation Shaders - Shadow Module (Modified)
    Added: PCSS Toggle & Manual Shadow Bias Control
--------------------------------------------------------------------------------
*/

// [0 1 2] 0: Hard Shadow (Fastest), 1: PCF (Medium), 2: PCSS (Physical Soft)
#define SHADOW_SOFT_TYPE 1 // [0 1 2]
#define PCF_SOFT_RADIUS 0.1 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0]
#define SHADOW_BIAS_STRENGTH 2.0 // [1.0 1.25 1.5 1.75 2.0 2.25 2.5 2.75 3.0 4.0 5.0 8.0 10.0 20.0] 调整此数值以消除阴影纹路(Shadow Acne)。数值越大，纹路越少，但影子越容易“飘起”。


#define PCSS_SEARCH_SAMPLES 8 // [0 1 2 4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]
#define PCSS_FILTER_SAMPLES 16 // [1 2 4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

//================================================================================================//

#include "Common.glsl"

vec3 WorldToShadowScreenSpace(in vec3 worldPos) {
    vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
    shadowClipPos = projMAD(shadowProjection, shadowClipPos);

    return DistortShadowSpace(shadowClipPos) * 0.5 + 0.5;
}

vec3 WorldToShadowScreenSpace(in vec3 worldPos, out float distortionFactor) {
    vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
    shadowClipPos = projMAD(shadowProjection, shadowClipPos);

    distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
    return DistortShadowSpace(shadowClipPos, distortionFactor) * 0.5 + 0.5;
}

//================================================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

// 遮挡物搜索 (PCSS专用)
float BlockerSearch(in vec3 shadowScreenPos, in float dither, in float searchScale) {
    float blockerDepth = 0.0;
    
    // 防止除以0导致的崩溃
    #if PCSS_SEARCH_SAMPLES > 0
        vec2 searchRadius = searchScale * diagonal2(shadowProjection);

        for (uint i = 0u; i < PCSS_SEARCH_SAMPLES; ++i) {
            vec2 sampleCoord = shadowScreenPos.xy + sampleVogelDisk(i, PCSS_SEARCH_SAMPLES, dither) * searchRadius;
            float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
            blockerDepth += saturate(shadowScreenPos.z - sampleDepth);
        }

        blockerDepth *= -5.0 / float(PCSS_SEARCH_SAMPLES);
        return blockerDepth * shadowProjectionInverse[2].z;
    #else
        return 0.0;
    #endif
}

// 水底焦散计算
vec3 CalculateWaterCaustics(in vec3 worldPos, in float waterDepth, in float dither) {
    vec3 surfacePos = worldPos - vec3(0.0, 1.0, 0.0);
    float caustics = 0.0;
    for (uint i = 0u; i < 16u; ++i) {
        vec3 samplePos = worldPos;
        samplePos.xz += sampleVogelDisk(i, 16, dither) * 0.15;

        vec2 sampleCoord = WorldToShadowScreenSpace(samplePos).xy;
        vec3 waveNormal = OctDecodeUnorm(texture(shadowcolor1, sampleCoord).xy);

        vec3 refractDir = refract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_IOR);
        vec3 refractedPos = samplePos + refractDir * abs(1.0 / refractDir.y);

        caustics += saturate(1.0 - 20.0 * distance(surfacePos, refractedPos));
    }
    return -smin(-caustics, -0.1, 0.15) * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}

// 核心采样过滤 (PCF/PCSS)
vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in vec3 worldPos, in float dither, in float blockerDepth) {
    const float rSteps = 1.0 / float(PCSS_FILTER_SAMPLES);
    
    vec2 penumbraRadius;
    // 使用宏定义的 PCF_SOFT_RADIUS 进行模糊半径控制
    #if SHADOW_SOFT_TYPE == 2
        penumbraRadius = min(sunAngularRadius * 2.0 * blockerDepth, 0.25) * diagonal2(shadowProjection);
    #elif SHADOW_SOFT_TYPE == 1
        penumbraRadius = PCF_SOFT_RADIUS * diagonal2(shadowProjection); 
    #else
        penumbraRadius = vec2(0.0); 
    #endif

    vec3 result = vec3(0.0);
    vec2 waterData = vec2(0.0);

    for (uint i = 0u; i < PCSS_FILTER_SAMPLES; ++i) {
        vec2 offset = sampleVogelDisk(i, PCSS_FILTER_SAMPLES, dither) * penumbraRadius;
        vec2 sampleCoord = shadowScreenPos.xy + offset;
        float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

    #ifdef COLORED_SHADOWS
        ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
        float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;

        if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
            float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
            if (waterMask > EPS) {
                waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
            } else {
                result += cube(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
            }
        } else
    #endif
        result += sampleDepth1;
    }

    result *= rSteps;

    #ifdef WATER_CAUSTICS
        if (waterData.y > EPS) {
            waterData.x /= waterData.y;
            float waterDepth = waterData.x * shadowProjectionInverse[2].z * 5.0;
            vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
            result = mix(result, caustics, waterData.y * rSteps);
        }
    #endif

    return result;
}

// 对外接口：计算PCSS/阴影
vec3 CalculatePCSS(in vec3 worldPos, in vec3 normalOffset, in float dither, out float blockerDepth) {
    blockerDepth = 0.0;
    float distortionFactor;
    
    // 应用自定义偏移倍率
    vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset * SHADOW_BIAS_STRENGTH, distortionFactor);
    shadowScreenPos.z -= 3e-8 * (1.0 + dither) * shadowProjectionInverse[1].y * distortionFactor * SHADOW_BIAS_STRENGTH;

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
    vec3 rayDir = ViewToScreenPos(viewLightDir * abs(viewPos.z) + viewPos) - rayPos;
    rayDir *= minOf((step(0.0, rayDir) - rayPos) / rayDir);
    rayDir *= inversesqrt(sdot(rayDir.xy));

    vec3 rayStep = rayDir * (0.05 / float(SCREEN_SPACE_SHADOWS_SAMPLES));
    rayPos += (dither + 0.5) * rayStep;

    float viewDistInv = inversesqrt(sdot(viewPos));
    float diffTolerance = 5e-4 * viewDistInv;
    float absorption = exp2(-0.125 / (viewDistInv * sssAmount));

    float result = 1.0;

    for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
        if (saturate(rayPos.xy) != rayPos.xy || result < 1e-2) break;

        ivec2 sampleTexel = uvToTexel(rayPos.xy);
        float sampleDepth = loadDepth0(sampleTexel);
        bool hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;

        #if defined LOD_MOD
            if (sampleDepth > 1.0 - EPS) {
                sampleDepth = loadDepth0Lod(sampleTexel);
                sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(sampleDepth));
                hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
            } else
        #endif
        if (hit) {
            vec2 samplePos = rayPos.xy * viewSize + 0.5;
            vec2 samplePosFloor = floor(samplePos);
            vec2 samplePosFract = samplePos - samplePosFloor;

            vec4 sh = textureGather(depthtex0, samplePosFloor * viewPixelSize);
            vec2 temp = mix(sh.wx, sh.zy, vec2(samplePosFract.x));
            sampleDepth = mix(temp.x, temp.y, samplePosFract.y);

            hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
        }

        result *= saturate(absorption + 1.0 - float(hit));
    }

    return result;
}