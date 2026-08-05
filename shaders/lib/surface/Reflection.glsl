/*
--------------------------------------------------------------------------------
    Revelation Shaders – Screen Space Reflection & Sky Fallback
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Added: Custom reflective block ID 10050 (no fallback).
    Metal fallback is now handled in the main deferred pass.
    Added: Selectable reflectivity criteria (metalness / roughness / both).
    Mode 2 now means "either metalness OR roughness" (not both).
    Added: NONMETAL_REFLECTION_BRIGHTNESS to boost non-metal reflections.
    Added: Non-metal materials now always skip sky reflection (only SSR).
    Added: Poisson-disk multi-sample Rough Reflections (8-tap, contact hardening, configurable steps & blur).
--------------------------------------------------------------------------------
*/

#include "/lib/surface/SSRT.glsl"

#ifndef METAL_SSR_MODE
    #define METAL_SSR_MODE 2 // [0 1 2]
#endif

// ====== 反射判定模式 ======
#ifndef METAL_REFLECT_MODE
    #define METAL_REFLECT_MODE 0   // [0 1 2]  0=仅金属度, 1=仅粗糙度, 2=金属度或粗糙度满足其一
#endif
#ifndef METALNESS_THRESHOLD
    #define METALNESS_THRESHOLD 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif
#ifndef ROUGHNESS_THRESHOLD
    #define ROUGHNESS_THRESHOLD 0.4 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif

// ====== 粗糙反射 (宏开关) ======
          // 开启粗糙反射
#ifndef ROUGH_REFLECTIONS_MAX
    #define ROUGH_REFLECTIONS_MAX 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] 粗糙反射的最高界限
#endif
#ifndef ROUGH_REFLECTION_STEPS
    #define ROUGH_REFLECTION_STEPS 6 // [2 4 6 8 10 12 16 24 32] 单独设置粗糙物体的 SSR 追踪步数（较低即可）
#endif
#ifndef ROUGH_REFLECTION_BLUR_STRENGTH
    #define ROUGH_REFLECTION_BLUR_STRENGTH 1.0 // [0.2 0.5 0.8 1.0 1.2 1.5 2.0 3.0 10.0 20.0 30.0 40.0 50.0 60.0 80.0 100.0 150.0] 粗糙反射的模糊强度倍率
#endif
#ifndef ROUGH_REFLECTION_BLUR_SAMPLES
    #define ROUGH_REFLECTION_BLUR_SAMPLES 6 // [4 6 8 10 12] 粗糙反射的泊松圆盘采样数（越多噪点越少，性能开销越大）
#endif
    //#define ROUGH_REFLECTION_CONTACT_HARDENING  // [注释以关闭] 接触硬化：近处清晰、远处模糊；关闭后使用固定模糊程度
    //#define ROUGH_REFLECTION_ON_METAL          // [注释以关闭] 粗糙反射模糊也对金属表面生效
#ifndef REFLECTION_METAL_ATTENUATION
    #define REFLECTION_METAL_ATTENUATION 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] 所有金属反射的固定衰减倍率（降低以透出金属本身纹理）
#endif
#ifndef REFLECTION_METAL_MIX
    #define REFLECTION_METAL_MIX 0.75 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] 金属反射与纹理的混合权重（1.0=纯反射, 0.0=纯纹理）
#endif

// ====== 反射亮度控制 ======
#ifndef REFLECTION_FALLBACK_BRIGHTNESS
    #define REFLECTION_FALLBACK_BRIGHTNESS 1.0 // [0.0 0.2 0.4 0.6 0.8 1.0 1.2 1.5 2.0]
#endif
#ifndef NONMETAL_REFLECTION_BRIGHTNESS
    #define NONMETAL_REFLECTION_BRIGHTNESS 4.0 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0]  增强非金属反射亮度
#endif
#ifndef REFLECTION_FALLBACK_BASE
    #define REFLECTION_FALLBACK_BASE 0.0 // 不再使用
#endif

#ifndef REFLECTION_NORMAL_BIAS
    #define REFLECTION_NORMAL_BIAS 0.0 // [0.0 0.0001 0.0003 0.0005 0.001 -0.001 -0.0005 -0.0001]
#endif

#define REFLECTION_GLOBAL
#define REFLECTION_SKY

// ---------- 快速 SSR 追踪器（模式 2）----------
#if METAL_SSR_MODE == 2
#ifdef SSRT_REFINEMENT
    const uint rayTraceBiSteps = uint(SSRT_REFINEMENT_STEPS);
#else
    const uint rayTraceBiSteps = 0u;
#endif

// 修改为动态接收 steps，以便常规反射和粗糙反射使用不同的步数
vec3 rayTraceScene(in vec3 screenPos, in vec3 viewPos, in vec3 rayDir, in float dither, in uint steps) {
    if (rayDir.z > -viewPos.z) return vec3(0.0);
    vec3 targetScreen = ViewToScreenPosRaw(viewPos + rayDir);
    float stepInv = 1.0 / float(steps);
    vec3 screenPosRayDir = normalize(targetScreen - screenPos) * stepInv;
    vec3 startPos = screenPos + screenPosRayDir * dither;
    
    for (uint i = 0u; i < steps; i++) {
        startPos += screenPosRayDir;
        if (startPos.x < 0.0 || startPos.y < 0.0 || startPos.x > 1.0 || startPos.y > 1.0) return vec3(0.0);
        float currDepth = textureLod(depthtex0, startPos.xy, 0).x;
        if (currDepth <= 0.56) return vec3(0.0);
        bool intersection = currDepth < startPos.z;
        if (intersection) {
            #if rayTraceBiSteps > 0
                for (uint j = 0u; j < rayTraceBiSteps; j++) {
                    if (textureLod(depthtex0, startPos.xy, 0).x >= 1.0) return vec3(0.0);
                    screenPosRayDir *= 0.5;
                    startPos += intersection ? -screenPosRayDir : screenPosRayDir;
                    currDepth = textureLod(depthtex0, startPos.xy, 0).x;
                    intersection = currDepth < startPos.z;
                }
            #else
                if (textureLod(depthtex0, startPos.xy, 0).x >= 1.0) return vec3(0.0);
            #endif
            return vec3(startPos.xy, 1.0);
        }
    }
    return vec3(0.0);
}
#endif

vec4 CalculateSpecularReflections(Material material, uint materialID, vec3 worldNormal, vec3 screenPos, vec3 worldDir, vec3 viewPos, float skylight, float dither) {
    #ifndef REFLECTION_GLOBAL
        return vec4(vec3(skylight * 1.3), 1.0);
    #endif

    // ---- 反射资格判定 ----
    bool isCustom = (materialID == 10050u);
    bool isReflective = isCustom;

    if (!isCustom) {
        #if METAL_REFLECT_MODE == 0
            isReflective = (material.metalness >= METALNESS_THRESHOLD);
        #elif METAL_REFLECT_MODE == 1
            isReflective = (material.roughness <= ROUGHNESS_THRESHOLD);
        #elif METAL_REFLECT_MODE == 2
            isReflective = (material.metalness >= METALNESS_THRESHOLD || material.roughness <= ROUGHNESS_THRESHOLD);
        #endif
    }

    // ---- 粗糙反射资格判定 ----
    bool isRoughReflective = false;
    #ifdef ROUGH_REFLECTIONS
        #ifdef ROUGH_REFLECTION_ON_METAL
        if (material.roughness > ROUGHNESS_THRESHOLD && material.roughness <= ROUGH_REFLECTIONS_MAX) {
            isRoughReflective = true;
        }
        #else
        if (!isReflective && material.roughness > ROUGHNESS_THRESHOLD && material.roughness <= ROUGH_REFLECTIONS_MAX) {
            isRoughReflective = true;
        }
        #endif
    #endif

    if (!isReflective && !isRoughReflective) return vec4(0.0);

    viewPos += mat3(gbufferModelView) * worldNormal * (length(viewPos) * REFLECTION_NORMAL_BIAS);

    // 天空方向：原始金属方向
    vec3 skyLightDir = reflect(worldDir, worldNormal);
    // SSR 方向：正确方向
    float NdotV = abs(dot(worldNormal, -worldDir));
    vec3 ssrRayDir = worldDir + worldNormal * (NdotV * 2.0);

    if (dot(worldNormal, skyLightDir) < EPS) return vec4(0.0);

    float fresnel = FresnelDielectricN(NdotV, 1.5);

    vec3 reflection = vec3(0.0);
    float reflectionDist = FP16_MAX;
    bool hasSky = false;
    bool hasSSR = false;

    // ---- 天空反射 ----
    #ifdef REFLECTION_SKY
        if (skylight > EPS && isEyeInWater == 0 ) {
            #if defined(DIMENSION_THE_END) || defined(DIMENSION_NETHER)
                reflection = AtmosphereSkyView(atmosphereViewPos, skyLightDir, worldSunDir);
            #else
                reflection = textureBicubic(skyMapTex, saturate(ProjectSky(skyLightDir))).rgb;
            #endif
            reflection *= smoothstep(0.3, 0.7, skylight) * REFLECTION_FALLBACK_BRIGHTNESS;
            
            if (isRoughReflective) reflection *= max(1.0 - material.roughness * 1.5, 0.1);
            
            hasSky = true;
        }
    #endif

    // ---- 屏幕空间反射 (SSR) ----
    #if METAL_SSR_MODE >= 1
        vec3 viewReflectDir = mat3(gbufferModelView) * ssrRayDir;
        bool traceHit = false;
        vec2 hitCoord;

        // 统一时空抖动噪声
        float ssrDither = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter).x;

        // 动态配置追踪步数：独立控制粗糙反射的采样数
        uint currentSteps = uint(SSRT_MAX_SAMPLES);
        #ifdef ROUGH_REFLECTIONS
            if (isRoughReflective) currentSteps = uint(ROUGH_REFLECTION_STEPS);
        #endif

        #if METAL_SSR_MODE == 1
            vec3 ssrScreenPos = screenPos;
            if (ScreenSpaceRaytrace(viewPos, viewReflectDir, ssrDither, currentSteps, ssrScreenPos)) {
                traceHit = true;
                hitCoord = ssrScreenPos.xy;
            }
        #elif METAL_SSR_MODE == 2
            vec3 traceResult = rayTraceScene(screenPos, viewPos, normalize(viewReflectDir), ssrDither, currentSteps);
            if (traceResult.z > 0.5) {
                traceHit = true;
                hitCoord = traceResult.xy;
            }
        #endif

        if (traceHit) {
            float edgeFade = hitCoord.x * hitCoord.y * oms(hitCoord.x) * oms(hitCoord.y);
            edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 1e3;
            
            ivec2 texel = uvToTexel(hitCoord * 0.5);
            float hitDepth = loadDepth0(texel);
            vec3 reflectViewPos = ScreenToViewPos(vec3(hitCoord * 0.5, hitDepth));
            reflectionDist = distance(reflectViewPos, viewPos);

            vec2 sampleUv = hitCoord * 0.5;

            // ==== 粗糙反射核心：泊松圆盘多采样模糊 ====
            #ifdef ROUGH_REFLECTIONS
            vec3 roughBlurredColor = vec3(0.0);
            if (isRoughReflective) {
                // 接触硬化：近处清晰，远处模糊（可通过宏开关切换为固定模糊）
                #ifdef ROUGH_REFLECTION_CONTACT_HARDENING
                float contactHardening = clamp(reflectionDist * 0.1, 0.0, 1.0);
                #else
                float contactHardening = 1.0;
                #endif
                
                // 模糊强度计算
                float blurRadius = material.roughness * material.roughness * 0.04 * ROUGH_REFLECTION_BLUR_STRENGTH * contactHardening;
                
                // 泊松圆盘采样点（最多12点，均匀覆盖单位圆，由 ROUGH_REFLECTION_BLUR_SAMPLES 控制实际使用数）
                const vec2 poissonDisk[12] = vec2[12](
                    vec2( 0.2369,  0.7892),
                    vec2(-0.7261,  0.3794),
                    vec2( 0.8163, -0.3127),
                    vec2(-0.3348, -0.8215),
                    vec2( 0.5482,  0.1273),
                    vec2(-0.0816,  0.6481),
                    vec2( 0.3794, -0.5261),
                    vec2(-0.5892, -0.1348),
                    vec2( 0.9134,  0.4032),
                    vec2(-0.8967, -0.4416),
                    vec2( 0.0521, -0.9518),
                    vec2(-0.4219,  0.8753)
                );
                
                // 随机旋转采样模式，避免网格伪影
                float angle = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter + 3).x * 6.2831853;
                float cosA = cos(angle);
                float sinA = sin(angle);
                vec2 aspectScale = vec2(viewHeight / viewWidth, 1.0);
                
                for (int i = 0; i < ROUGH_REFLECTION_BLUR_SAMPLES; i++) {
                    vec2 offset = poissonDisk[i];
                    vec2 rotatedOffset = vec2(
                        offset.x * cosA - offset.y * sinA,
                        offset.x * sinA + offset.y * cosA
                    );
                    vec2 sampleCoord = sampleUv + rotatedOffset * blurRadius * aspectScale;
                    sampleCoord = clamp(sampleCoord, 0.001, 0.499);
                    roughBlurredColor += texture(colortex4, sampleCoord).rgb;
                }
                roughBlurredColor /= float(ROUGH_REFLECTION_BLUR_SAMPLES);
            }
            #endif

            float clampedFresnel = fresnel;
            if (material.metalness >= METALNESS_THRESHOLD) {
                // 金属：固定衰减，透出金属本身纹理
                clampedFresnel = fresnel * REFLECTION_METAL_ATTENUATION;
            } else {
                clampedFresnel = min(fresnel, 0.5);
                if (isRoughReflective) {
                    clampedFresnel *= max(1.0 - material.roughness, 0.1);
                }
            }
            
            // SSR 颜色采样：粗糙反射使用泊松圆盘多采样模糊，常规反射使用单次采样
            #ifdef ROUGH_REFLECTIONS
            vec3 ssrColor = (isRoughReflective ? roughBlurredColor : texture(colortex4, sampleUv).rgb) * clampedFresnel;
            #else
            vec3 ssrColor = texture(colortex4, sampleUv).rgb * clampedFresnel;
            #endif
            reflection = mix(reflection, ssrColor, saturate(edgeFade));
            hasSSR = true;
        }
    #endif

    // ---- 非金属反射亮度增强 ----
    if ((isReflective || isRoughReflective) && material.metalness < METALNESS_THRESHOLD) {
        reflection *= NONMETAL_REFLECTION_BRIGHTNESS;
    }

    if (!hasSky && !hasSSR) {
        return vec4(0.0, 0.0, 0.0, FP16_MAX);
    }

    if (!hasSSR) reflectionDist = FP16_MAX;
    
    return vec4(reflection, reflectionDist);
}