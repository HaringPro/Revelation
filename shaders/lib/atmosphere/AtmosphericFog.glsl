/*
--------------------------------------------------------------------------------
    Revelation Shaders - High Performance Analytical Fog Engine
    (Visual match with original raymarching version + horizon fix + noise macro)
    Optimizations: Three-point Simpson integration, no loops.
    Keeps all original macros, adds FOG_NOISE_ENABLED for noise toggle.
    Fake horizon blending temporarily removed.
    Now VF_DENSITY_MULT correctly scales overall fog density.
    ✨ 进一步优化：exp → exp2，末地分支散射逻辑简化。
    ✨ 新增：VF_SUNLIGHT_TINT_RATIO (仅主世界) 控制雾气跟随阳光颜色。
    ✨ 动态染色：强度随太阳高度变化，正午最强，傍晚减弱，晚上消失。
    ✨ 末地雾气已为淡紫色调。
--------------------------------------------------------------------------------
*/

#ifndef VF_SHADOW_QUALITY
    #define VF_SHADOW_QUALITY 1
#endif

// =================【 雾气全局浓度控制阀 】=================
#ifndef VF_DENSITY_MULT
    #define VF_DENSITY_MULT 0.25 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0]
#endif

// =================【 阳光染色最大强度 (仅主世界，实际强度会随太阳高度变化) 】=================
#ifndef VF_SUNLIGHT_TINT_RATIO
    #define VF_SUNLIGHT_TINT_RATIO 0.9 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif
// =========================================================
#define NOISE_SIZE 0.01 // [0.005 0.006 0.007 0.008 0.009 0.01 0.0125 0.015 0.02 0.025 0.03 0.04 0.05 0.1 1 10 100]
// 噪声开关：定义此宏以启用 3D 噪声（更真实），注释掉则禁用（更快）
//#define FOG_NOISE_ENABLED

#include "/lib/atmosphere/Rainbow.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

uniform float biomeSandstorm;
uniform float biomeSnowstorm;
uniform float biomeGreenVapor;

//================================================================================================//

const vec2 FOG_HEIGHT_FALLOFF = vec2(-0.03125, -0.08333); // x: Rayleigh, y: Mie

#ifdef FOG_NOISE_ENABLED
// Medium-quality 3D noise (matches original VF_NOISE_QUALITY == MEDIUM)
float GetFogNoise(vec3 pos) {
    vec3 windOffset = vec3(0.07, 0.04, 0.05) * worldTimeCounter;
    pos *= NOISE_SIZE;
    pos -= windOffset;
    float noise = Pseudo3DNoise(pos) * 2.5;
    noise -= Pseudo3DNoise(pos * 4.0 - windOffset);
    return noise;
}
#endif

vec2 CalculateFogDensity(in vec3 rayPos, in float uniformFog) {
    vec3 worldPos = rayPos + cameraPosition;

    float heightDiff = abs(worldPos.y - VF_HEIGHT) * oms(step(worldPos.y, VF_HEIGHT) * 0.5);
    vec2 density = exp2(heightDiff * FOG_HEIGHT_FALLOFF);

#ifdef FOG_NOISE_ENABLED
    float noise = GetFogNoise(worldPos);
    density.y *= sqr(noise) * (2.0 + biomeSandstorm * 8.0 + biomeSnowstorm * 4.0);
#else
    density.y *= (2.0 + biomeSandstorm * 8.0 + biomeSnowstorm * 4.0);
#endif

    // Uniform fog with linearstep falloff
    density += uniformFog * linearstep(cumulusTopAltitude, cumulusBottomAltitude, worldPos.y);

    return max(density, vec2(0.0));
}

//================================================================================================//

#if !defined CLOUD_SHADOWS || defined PASS_SKY_MAP
    #undef VF_CLOUD_SHADOWS
#endif

mat2x3 RaymarchAtmosphericFog(in vec3 startPos, in vec3 endPos, in float dither, in bool skyMask, in uint steps) {
    vec3 dirDelta = endPos - startPos;
    float rayLengthSq = dot(dirDelta, dirDelta);
    if (rayLengthSq < 1e-6) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    float norm = inversesqrt(rayLengthSq);
    float rayLength = rayLengthSq * norm;
    vec3 worldDir = dirDelta * norm;
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!雾气最大累计距离
    float maxDist = min(lodRenderDist, 256.0); 
    if (skyMask) {
        float safeDirY = max(abs(worldDir.y), 1e-5) * sign(worldDir.y + 1e-6);
        rayLength = clamp((cumulusTopRadius - atmosphereViewHeight) / safeDirY, 0.0, maxDist);
    }

    vec3 midPos = startPos + worldDir * (rayLength * 0.5);
    vec3 endPoint = startPos + worldDir * rayLength;

    float LdotV = dot(worldLightDir, worldDir);
    vec2 phase = AtmospherePhase(LdotV);

    float rainFactor = 1.0 + wetness * VF_MIE_DENSITY_RAIN_MULT;
    float mieDensityMult = VF_MIE_DENSITY * 5e2 * rainFactor;
    #ifdef VF_TIME_FADE
        mieDensityMult *= max(wetness, 1.5 - approxSqrt(max(timeNoon, 0.0)) * 1.5 - timeSunset * 0.75 - timeMidnight * 0.5);
    #endif

    vec3 fogMieExtinction = atmosphere.mieExtinction * mieDensityMult;
    vec3 fogMieScattering = atmosphere.mieScattering * mieDensityMult;

    #ifdef PER_BIOME_FOG
        vec3 biomeAlbedo = mix(vec3(1.0), vec3(1.1, 0.9, 0.7), biomeSandstorm);
        biomeAlbedo = mix(biomeAlbedo, vec3(0.95, 1.1, 1.0), biomeGreenVapor);
        fogMieScattering *= biomeAlbedo;
    #endif

    mat2x3 fogExtinctionCoeff = mat2x3(
        atmosphere.rayleighScattering * (VF_RAYLEIGH_DENSITY * 16.0),
        fogMieExtinction
    );
    mat2x3 fogScatteringCoeff = mat2x3(
        atmosphere.rayleighScattering * (VF_RAYLEIGH_DENSITY * 16.0),
        fogMieScattering
    );

    float uniformFog = (8.0 * rainFactor) / maxDist;

    // Simpson integration
    vec2 densityStart = CalculateFogDensity(startPos, uniformFog);
    vec2 densityMid   = CalculateFogDensity(midPos, uniformFog);
    vec2 densityEnd   = CalculateFogDensity(endPoint, uniformFog);
    vec2 avgDensity   = (densityStart + densityMid * 2.0 + densityEnd) * 0.25;

    // ---- 全局浓度控制（在此生效） ----
    avgDensity *= VF_DENSITY_MULT;

    // ---- 天空路径与几何路径的密度调节 ----
    if (skyMask) {
        // 天空路径不应用室内消隐
    } else {
        // 几何体路径：依据天空光照微弱减弱密度，防止室内/地下过度积雾
        avgDensity *= clamp(eyeSkylightSmooth * 0.8 + 0.2, 0.0, 1.0);
    }

    if (dot(avgDensity, vec2(1.0)) < 1e-5) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    vec3 sampleShadow = vec3(1.0);
    #if defined PASS_VOLUMETRIC_FOG && VF_SHADOW_QUALITY > 1
        float shadowFade = smoothstep(128.0, 192.0, rayLength);
        if (shadowFade < 1.0) {
            vec3 shadowViewPos = transMAD(shadowModelView, midPos);
            vec3 shadowProjPos = projMAD(shadowProjection, shadowViewPos);
            vec3 shadowScreenPos = DistortShadowSpace(shadowProjPos) * 0.5 + 0.5;
            #ifdef ENABLE_VOXELIZATION
                ShiftShadowScreenPos(shadowScreenPos.xy); // 体素平铺布局：真阴影右上区
            #endif
            
            if (saturate(shadowScreenPos) == shadowScreenPos) {
                ivec2 texelLimit = ivec2(realShadowMapRes) - 1;
                ivec2 shadowTexel = clamp(ivec2(shadowScreenPos.xy * realShadowMapRes), ivec2(0), texelLimit);
                
                #ifdef COLORED_VOLUMETRIC_FOG
                    float sampleShadowX = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x);
                    float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, shadowTexel, 0).x);
                    if (sampleShadowX != sampleDepth0) {
                        vec3 shadowColorSample = max(texelFetch(shadowcolor0, shadowTexel, 0).rgb, vec3(0.0));
                        shadowColorSample *= shadowColorSample; // optimized square
                        sampleShadow = shadowColorSample * (sampleShadowX - sampleDepth0) + vec3(sampleDepth0);
                    } else {
                        sampleShadow = vec3(sampleShadowX);
                    }
                #else
                    sampleShadow = vec3(step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x));
                #endif

                if (shadowFade > 0.0) {
                    sampleShadow = mix(sampleShadow, vec3(1.0), shadowFade);
                }
            }
        }
    #endif

    #ifdef VF_CLOUD_SHADOWS
        if (midPos.y < cumulusTopAltitude + 64.0) {
            vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(midPos).xy;
            if (saturate(cloudShadowCoord) == cloudShadowCoord) {
                sampleShadow *= texture(cloudShadowTex, cloudShadowCoord).x;
            }
        }
    #endif

    vec2 opticalDepthSun = avgDensity * (4.0 * clamp(worldLightDir.y, 0.2, 1.0));
    vec2 msV = 0.9 * oms(exp2(-8.0 * avgDensity));

    // ✨ 优化：exp 替换为 exp2
    vec2 msEnergy = phase * exp2(-opticalDepthSun * 1.442695);
    
    vec2 denom = max(oms(msV) * (1.0 + opticalDepthSun * 0.25), vec2(1e-4));
    msEnergy += uniformPhase * msV / denom;

    vec3 totalExtinction = fogExtinctionCoeff * avgDensity;
    vec3 safeExtinction = max(totalExtinction, vec3(1e-5));
    vec3 transmittance = exp2(-clamp(rayLength, 0.0, maxDist) * safeExtinction * 1.442695);
    
    vec3 integralFactor = (vec3(1.0) - transmittance) / safeExtinction;



    vec3 scatteringSun = fogScatteringCoeff * (avgDensity * msEnergy) * integralFactor * sampleShadow;
    vec3 scatteringSky = fogScatteringCoeff * avgDensity * integralFactor;

    #ifndef VF_CLOUD_SHADOWS
        scatteringSun *= max(1.0 - wetness * CLOUD_SHADOW_STRENGTH, 0.0);
    #endif
    #if !defined PASS_VOLUMETRIC_FOG
        scatteringSun *= eyeSkylightSmooth * eyeSkylightSmooth; // 平方衰减，减少暗处穿透
    #endif

    scatteringSky *= eyeSkylightSmooth;

    #ifdef RAINBOWS
        float visibility = wetness * oms(rainStrength);
        if (visibility > EPS) {
            float distanceFade = saturate(rayLength / max(maxDist, 1.0)) * visibility;
            scatteringSun *= 1.0 + RenderRainbows(LdotV) * distanceFade;
        }
    #endif

    vec3 scattering = scatteringSun * global.directIlluminance;
    scattering += scatteringSky * uniformPhase * global.skyUpIlluminance;

    // ---------- 维度专属色调处理 ----------
    #ifdef DIMENSION_THE_END
        // 末地淡紫色雾气（固定强度）
        const vec3 fogPurpleTint = vec3(0.75, 0.50, 0.85);
        const float fogPurpleStrength = 0.3;
        scattering *= fogPurpleTint * fogPurpleStrength;
    #else
        // ---- 主世界阳光染色，强度随太阳高度动态变化 ----
        // 正午 worldSunDir.y ≈ 1 → timeBasedTint ≈ 1；傍晚 ≈ 0 → 0；夜晚 < 0 → 0
        float timeBasedTint = saturate(worldSunDir.y * 2.5 - 0.15);
        float tintStrength = VF_SUNLIGHT_TINT_RATIO * timeBasedTint;
        if (tintStrength > 0.0) {
            vec3 sunTint = global.directIlluminance / max(luminance(global.directIlluminance), EPS);
            scattering = mix(scattering, scattering * sunTint, tintStrength);
        }
    #endif

    
    return mat2x3(max(scattering, vec3(0.0)), clamp(transmittance, 0.0, 1.0));
}