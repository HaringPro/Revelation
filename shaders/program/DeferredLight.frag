/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Deferred lighting and sky combination
    Optimized: Early sun-light culling, deferred bicubic sampling, constant folding.
    Added: SSS_DISABLE_BEYOND_SHADOW_DIST macro to skip SSS outside shadow distance.
    Added: SPECULAR_BLOOM_BOOST for enhancing specular bloom (glare).
    Added: Skip compensation in The End / Nether.
    Added: SUN_BRIGHTNESS_MULTIPLIER and MOON_BRIGHTNESS_MULTIPLIER for independent tuning.
    Added: AMBIENT_BRIGHTNESS_MULTIPLIER and AMBIENT_COLOR_TINT to control ambient/skylight.
    Added: AMBIENT_SUNLIGHT_TINT_RATIO with dynamic time‑based intensity (noon max, night off).
    Added: NIGHT_SHADOW_BOOST to deepen night shadows.
--------------------------------------------------------------------------------
*/

#define PASS_DEFERRED_LIGHTING

#ifndef SHADOW_CONTRAST_STRENGTH
    #define SHADOW_CONTRAST_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 1.0 2.0 3.0 4.0 6.0 8.0 10.0]
#endif

// 启用补偿
#define COMPENSATION_ENABLED

// 补偿参数
#ifndef COMPENSATION_BOOST
    #define COMPENSATION_BOOST 0.5 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif
#ifndef COMPENSATION_FADE_SPEED
    #define COMPENSATION_FADE_SPEED 0.2 // [0.1 0.2 0.3 0.4 0.5 1.0 2.0 3.0 4.0 6.0 8.0 10.0]
#endif
#ifndef COMPENSATION_DELAY
    #define COMPENSATION_DELAY 6.0 // [0.0 0.5 1.0 1.5 2.0 3.0 5.0 6.0 10.0 15.0]
#endif
#ifndef COMPENSATION_AO_BOOST
    #define COMPENSATION_AO_BOOST 1.5 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0]
#endif

// ====== 次表面散射距离控制 ======
#define SSS_DISABLE_BEYOND_SHADOW_DIST

// ====== 镜面高光泛光增强 ======
#ifndef SPECULAR_BLOOM_BOOST
    #define SPECULAR_BLOOM_BOOST 3.0 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0]
#endif

// ====== 阳光 / 月光亮度控制 ======
#ifndef SUN_BRIGHTNESS_MULTIPLIER
    #define SUN_BRIGHTNESS_MULTIPLIER 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0 5.0]
#endif
#ifndef MOON_BRIGHTNESS_MULTIPLIER
    #define MOON_BRIGHTNESS_MULTIPLIER 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0 5.0]
#endif

// ====== 环境光/天空光亮度与颜色控制 ======
#ifndef AMBIENT_BRIGHTNESS_MULTIPLIER
    #define AMBIENT_BRIGHTNESS_MULTIPLIER 1.5 // [0.0 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#endif
#ifndef AMBIENT_COLOR_TINT
    #define AMBIENT_COLOR_TINT vec3(1.0, 1.0, 1.0) // 减少蓝色可改为 vec3(1.0, 1.0, 0.85)
#endif

// 环境光阳光色调混合最大强度 (实际强度 = 此值 × 太阳高度因子，仅主世界)
#ifndef AMBIENT_SUNLIGHT_TINT_RATIO
    #define AMBIENT_SUNLIGHT_TINT_RATIO 1.1 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0]
#endif

// ====== 夜间阴影增强 ======
#ifndef NIGHT_SHADOW_BOOST
    #define NIGHT_SHADOW_BOOST 4.5 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0]
#endif

// ====== Precomputed Constants ======
#define INV_HAND_DEPTH (1.0 / MC_HAND_DEPTH)
#define HAND_DEPTH_OFFSET (0.5 - 0.5 * INV_HAND_DEPTH)
#define SSS_CONTRAST_POW (1.2 / SHADOW_CONTRAST_STRENGTH)

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"



//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 sceneOut;

//======// Uniform //=============================================================================//

writeonly uniform uimage2D colorimg7;
uniform sampler2D cloudOriginTex;

#include "/lib/universal/Uniform.glsl"

// 覆盖只读限制，使 GlobalData 可写
#undef SSBO_DECLARED_TPYE
#define SSBO_DECLARED_TPYE
#include "/lib/universal/SSBO.glsl"

//======// Struct //================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Celestial.glsl"

#include "/lib/atmosphere/clouds/Render.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

#include "/lib/lighting/Common.glsl"
#include "/lib/lighting/shadow/Render.glsl"

#if AO_ENABLED > 0 && !defined SSILVB_ENABLED
    #include "/lib/lighting/SSAO.glsl"
    #include "/lib/lighting/GTAO.glsl"
#endif

#include "/lib/SpatialUpscale.glsl"

#ifdef RAIN_PUDDLES
    #include "/lib/surface/RainPuddle.glsl"
#endif
#include "/lib/surface/Reflection.glsl"

//#ifdef ENABLE_VOXELIZATION
    #include "/lib/lighting/VoxelGI.glsl"
//#endif

// 方块图集（shaders.properties customTexture.atlas2D = blocks.png，与传播端/体素化同图集）
// 无显式 binding：交由 Iris 按名字自动绑定（显式 binding 会与普通贴图纹理单元冲突）
uniform sampler2D atlas2D;

// 真阳光直射可见度（像素版，与传播端 VoxelSunVisibility 同逻辑，供调试标色）
// 阴影贴图单点硬件深度比较：0=被挡，1=直射；太阳在地平线以下=false
bool VoxelPixelSunVisible(vec3 relPos) {
    if (sunPosition.y < 0.01) return false;
    float distortionFactor;
    vec3 ssp = WorldToShadowScreenSpace(relPos, distortionFactor);
    ssp.z -= 3e-8 * shadowProjInv1y * distortionFactor * SHADOW_BIAS_STRENGTH;
    if (all(equal(ssp, saturate(ssp)))) {
        return textureLod(shadowtex1, vec3(ssp.xy, ssp.z), 0).x > 0.5;
    }
    return true;
}

// 每像素漫反射追踪已迁到 DiffuseIndirect.comp（棋盘半分辨率 1 SPP + SVGF 时域累积，
// 阶段④）；此处只读回信号，不再 include VoxelTracing.glsl。
// VoxelPixelSunVisible（真阳光直射可见度）供 DEBUG_VOXEL_GI 标色，独立于追踪端。


//======// Main //================================================================================//
void main() {
    
    ivec2 texelPos = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    vec3 screenPos = vec3(screenCoord, loadDepth0(texelPos));

    #if defined LOD_MOD
        bool lodMask = screenPos.z > 1.0 - EPS;
        if (lodMask) {
            screenPos.z = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth0Lod(texelPos)));
        }
    #endif

    if (screenPos.z < 0.56) {
        screenPos.z = screenPos.z * INV_HAND_DEPTH + HAND_DEPTH_OFFSET;
    }

    vec3 viewPos = ScreenToViewPos(screenPos);
    vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
    // 相机相对世界坐标备份：L224 会把 worldPos 改成绝对坐标，但 gbufferModelViewInverse
    // 不含相机平移（Terrain.vert L98 证据），L224 加的不是 cameraPosition，其后 worldPos
    // 并非真正的绝对坐标——GI 查询/追踪/调试一律用本备份（确定正确的相机相对），
    // 不要再做 worldPos - cameraPosition（双重减 → 全越界 → GI 恒 0/全红诊断）。
    vec3 camRelPos = worldPos;
    vec3 worldDir = normalize(worldPos);

    uvec4 materialPack = loadMaterialPack(texelPos);
    uint materialID = materialPack.y;
    vec3 albedo = sRGBToLinear(loadAlbedo(texelPos));
    float dither = BlueNoise(texelPos, frameCounter);

    sceneOut = vec3(0.0);

    // ========== Sky ==========
    if (materialID == 0u) {
        vec3 transmittance = AtmosphereTransmittanceToPoint(atmosphereViewPos, worldDir);
        vec3 skyRadiance = AtmosphereSkyView(atmosphereViewPos, worldDir, worldSunDir);
        sceneOut = skyRadiance;

        #ifdef CLOUDS
            #ifdef CLOUD_TAAU_ENABLED
                vec4 cloudData = texture(cloudReconstructTex, screenCoord);
            #else
                screenCoord += viewPixelSize * (dither - 0.5);
                vec4 cloudData = texture(cloudOriginTex, screenCoord);
            #endif
            CompositeClouds(sceneOut, cloudData, worldDir);
            transmittance *= cloudData.w;
        #endif

        if (dot(transmittance, vec3(1.0)) > EPS) {
            vec3 celestial = RenderSun(worldDir, worldSunDir);
            vec3 vanillaMoon = albedo * MOON_BRIGHTNESS_MULTIPLIER;   // 月光亮度控制
            #ifdef GALAXY
                celestial += mix(RenderGalaxy(worldDir), vanillaMoon, step(0.06, vanillaMoon.g));
            #else
                celestial += mix(RenderStars(worldDir), vanillaMoon, step(0.06, vanillaMoon.g));
            #endif
            sceneOut += celestial * transmittance;
        }
        imageStore(colorimg7, texelPos, uvec4(0));
        return;
    }

    // ========== Geometry ==========
    worldPos += gbufferModelViewInverse[3].xyz;
    vec3 geoNormal, worldNormal;
    FetchNormalData(texelPos, geoNormal, worldNormal);
    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;
    vec2 lightmap = Unpack2x8U(materialPack.x);

    #if defined MC_SPECULAR_MAP
        vec4 specularTex = ExtractSpecularTex(materialPack);
    #else
        vec4 specularTex = vec4(0.0);
    #endif

    #ifdef RAIN_PUDDLES
        if (wetnessCustom > EPS) {
            if (materialID < 1000u || materialID > 1002u) {
                CalculateRainPuddles(albedo, worldNormal, specularTex.rgb, worldPos, geoNormal, lightmap.y);
                materialPack.z = Packup2x8U(specularTex.xy);
                imageStore(colorimg7, texelPos, materialPack);
            }
        }
    #endif

    Material material = GetMaterialData(specularTex);
    float sssAmount = 0.0;
    
    // --- SSS ---
    #if SHADOW_SOFT_TYPE > 0
        #if SUBSURFACE_SCATTERING_MODE < 2
            switch (materialID) {
                case 1000u: case 1001u: case 1002u: case 1003u: case 27u: case 28u: sssAmount = 0.6; break;
                case 13u: sssAmount = 0.8; break;
                case 37u: case 39u: sssAmount = 0.5; break;
                case 38u: case 51u: sssAmount = 0.8; break;
                case 40u: sssAmount = 0.3; break;
            }
        #endif
        #if TEXTURE_FORMAT == 0 && SUBSURFACE_SCATTERING_MODE > 0 && defined MC_SPECULAR_MAP
            if (specularTex.b > 64.5 / 255.0) sssAmount = max(sssAmount, specularTex.b);
        #endif

        sssAmount = linearstep(64.0 / 255.0, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;
    #endif

    // --- Optimized Direct Light & Shadow Calculation ---
    float sunlightFactor = saturate(lightmap.y * 1e6 + float(isEyeInWater));
    vec3 sunlightBase = vec3(0.0);
    float cloudShadow = 1.0;

    if (sunlightFactor > EPS) {
        #ifdef CLOUD_SHADOWS
            vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(worldPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
            cloudShadow = textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
        #else
            cloudShadow = 1.0 - wetness * 0.96;
        #endif
        
        // ---------- 末地夜晚直接光（淡紫色、更暗）----------
        #ifdef DIMENSION_THE_END
            const vec3 nightDirectTint = vec3(0.75, 0.45, 0.80);
            const float nightDirectScale = 0.20; // 更暗
            sunlightBase = cloudShadow * sunlightFactor * global.directIlluminance * nightDirectTint * nightDirectScale;
        #else
            sunlightBase = cloudShadow * sunlightFactor * global.directIlluminance;
        #endif
    }
    sunlightBase *= SUN_BRIGHTNESS_MULTIPLIER; // 阳光亮度控制

    vec3 specularDirect = vec3(0.0);
    float worldDistSquared = sdot(worldPos);
    
    float distXZSq = dot(worldPos.xz, worldPos.xz);
    float distanceFade = linearstep(shadowDistance - 8.0, shadowDistance, approxSqrt(distXZSq));
    #if defined LOD_MOD
        distanceFade = saturate(distanceFade + float(lodMask));
    #endif

    float NdotL = saturate(dot(worldNormal, worldLightDir));

    if (sunlightFactor > EPS && (NdotL + sssAmount > EPS)) {
        vec3 shadow = vec3(NdotL);
        float surfaceDepth = 0.0;
        float normalOffsetBase = (approxSqrt(worldDistSquared) * 2e-3 + 2e-2) * (2.0 - NdotL);
        
        vec3 rawShadow = vec3(1.0);

        if (distanceFade < EPS) {
            rawShadow = CalculatePCSS(worldPos, geoNormal * normalOffsetBase, dither, surfaceDepth);
            
            #if SHADOW_SOFT_TYPE == 1
                shadow *= pow(rawShadow, vec3(SHADOW_CONTRAST_STRENGTH));
                shadow = smoothstep(-0.01, 1.01, shadow);
            #else
                shadow *= rawShadow;
            #endif
        }

        #ifdef SCREEN_SPACE_SHADOWS
            float contactShadow = ScreenSpaceShadow(screenPos, viewPos + viewNormal * normalOffsetBase, dither, sssAmount);
        #else
            const float contactShadow = 1.0;
        #endif

        float LdotV = dot(worldLightDir, -worldDir);

        #ifdef SSS_DISABLE_BEYOND_SHADOW_DIST
    bool sssAllowed = (distanceFade < EPS);
#else
    // 过渡区 (0 < distanceFade < 1) 禁用 SSS，因为 surfaceDepth 无效
    bool sssAllowed = (distanceFade < EPS) || (distanceFade >= 1.0 - EPS);
#endif

        if (sssAllowed && sssAmount > EPS) {
            vec3 beta = approxSqrt(normalize(albedo));
            vec3 sigmaA = oms(beta) * 16.0 / (sssAmount * SUBSURFACE_SCATTERING_STRENGTH);
            vec3 sigmaS = 4.0 * beta * sssAmount;
            float phase = HenyeyGreensteinPhase(-LdotV, 0.7) * 0.25 + uniformPhase * 0.75;
            vec3 sss = sigmaS * phase * exp2(-rLOG2 * surfaceDepth * (sigmaS + sigmaA));

            #if SHADOW_SOFT_TYPE == 1
                float sssMask = saturate(dot(rawShadow, vec3(0.3333)));
                sss *= pow(sssMask, SSS_CONTRAST_POW);
            #endif

            float cutout = float(clamp(materialID, 1000u, 1003u) == materialID || clamp(materialID, 27u, 28u) == materialID);
            sss *= mix(1.0, contactShadow, saturate(distanceFade + cutout * 0.75));
            sceneOut += sunlightBase * sss * SUBSURFACE_SCATTERING_BRIGHTNESS;
        }

        if (dot(shadow, vec3(1.0)) > EPS) {
            // ---------- 夜间阴影增强 ----------
            float isNight = step(0.0, -worldSunDir.y);
            shadow = pow(shadow, vec3(mix(1.0, NIGHT_SHADOW_BOOST, isNight)));

            shadow *= contactShadow * sunlightBase;
            #ifdef PARALLAX_SHADOW
                #if defined PARALLAX && !defined PARALLAX_DEPTH_WRITE
                    shadow *= oms(loadSceneMain(texelPos).x);
                #endif
            #endif

            vec3 halfway = normalize(worldLightDir - worldDir);
            float NdotV = abs(dot(worldNormal, worldDir)), NdotH = dot(worldNormal, halfway), LdotH = dot(worldLightDir, halfway);
            sceneOut += shadow * DiffuseBurley(LdotH, NdotV, NdotL, material.roughness);

            #if defined MC_SPECULAR_MAP
                vec3 f0 = GetMaterialF0(material.metalness, albedo);
            #else
                const vec3 f0 = vec3(DEFAULT_DIELECTRIC_F0);
            #endif
            specularDirect = shadow * SpecularGGX(LdotH, NdotV, NdotL, NdotH, material.roughness, f0);
            specularDirect *= SPECULAR_BLOOM_BOOST;
        }
    }

    // ====== Ambient Occlusion ======
    #if AO_ENABLED > 0 && !defined SSILVB_ENABLED
        float aoVal = 1.0;
        #if AO_ENABLED == 1
            aoVal = CalculateSSAO(screenCoord, viewPos, viewNormal, SampleStbnUnitvec2(texelPos, frameCounter));
        #else
            aoVal = CalculateGTAO(screenCoord, viewPos, viewNormal, SampleStbnVec2(texelPos, frameCounter));
        #endif
        
        vec3 ao;
        #ifdef AO_MULTI_BOUNCE
            ao = ApproxMultiBounce(aoVal, albedo);
        #else
            ao = vec3(aoVal);
        #endif
    #else
        const vec3 ao = vec3(1.0);
    #endif

    // ====== 末地 / 地狱跳过补偿逻辑 ======
    #ifdef DIMENSION_THE_END
        #undef COMPENSATION_ENABLED
    #endif
    #ifdef DIMENSION_NETHER
        #undef COMPENSATION_ENABLED
    #endif

    // ====== 补偿逻辑 ======
    float activeMinAmbient = MINIMUM_AMBIENT_BRIGHTNESS;
    float compensationAlpha = 0.0;

        #ifdef COMPENSATION_ENABLED
        if (texelPos == ivec2(0,0)) {
            bool skyVisible = false;
            const int grid = 4;
            for (int gy = 0; gy < grid && !skyVisible; gy++) {
                for (int gx = 0; gx < grid; gx++) {
                    vec2 uv = (vec2(gx, gy) + 0.5) / float(grid);
                    ivec2 sampleTexel = ivec2(uv * viewSize);
                    uint sampleMaterial = texelFetch(colortex7, sampleTexel, 0).y;
                    if (sampleMaterial == 0u) {
                        skyVisible = true;
                        break;
                    }
                }
            }

            float currentTime = frameTimeCounter;
            float lastTime = global.lastSkyTime;
            float alpha = global.compensationAlpha;

            // 夜晚关闭补偿：太阳在地平线下时 worldSunDir.y < 0，强制 alpha = 0
            float isNight = step(0.0, -worldSunDir.y);
            if (isNight > 0.5) {
                alpha = 0.0;
            } else {
                if (skyVisible) {
                    lastTime = currentTime;
                    alpha = clamp(alpha + COMPENSATION_FADE_SPEED * frameTime, 0.0, 1.0);
                } else {
                    if (currentTime - lastTime > COMPENSATION_DELAY) {
                        alpha = clamp(alpha - COMPENSATION_FADE_SPEED * frameTime, 0.0, 1.0);
                    }
                }
            }

            global.compensationAlpha = alpha;
            global.lastSkyTime = lastTime;
        }

        compensationAlpha = global.compensationAlpha;
        activeMinAmbient = MINIMUM_AMBIENT_BRIGHTNESS + COMPENSATION_BOOST * compensationAlpha;
    #endif

    // 环境光累积
    vec3 ambientAccum = vec3((worldNormal.y * 0.4 + 0.6) * max(activeMinAmbient, 5e-3 * nightVision));

    #ifndef SSILVB_ENABLED
        if (lightmap.y > EPS) {
            float lm3 = cube(lightmap.y);
            vec3 skyAmbient = ConvolvedReconstructSH3(global.skySH, worldNormal) * lm3;
            skyAmbient += CalculateFakeBouncedLight(worldNormal) * lm3 * (lightmap.y * lightmap.y) * sunlightBase;
            // 体素 GI 开启时：按 VOXEL_GI_BLENDED_LIGHTMAP 混合原版天空 Lightmap
            // （0.0=完全屏蔽原版，间接光照仅由体素 GI 提供；1.0=完全保留）
            #ifdef VOXEL_GI_ENABLED
                skyAmbient *= VOXEL_GI_BLENDED_LIGHTMAP;
            #endif
            ambientAccum += skyAmbient;
        }
    #endif

    // ---------- 末地夜晚环境光调整（淡紫色、更暗）----------
    #ifdef DIMENSION_THE_END
        const vec3 nightAmbientTint = vec3(0.65, 0.45, 0.70);
        const float nightAmbientScale = 0.25;
        ambientAccum *= nightAmbientTint * nightAmbientScale;
    #endif

    vec3 finalAo = ao;
    #ifdef COMPENSATION_ENABLED
        float localDarkness = 1.0 - saturate(lightmap.y * 5.0);
        float aoEnhanceWeight = compensationAlpha * localDarkness;
        finalAo = pow(finalAo, vec3(1.0 + COMPENSATION_AO_BOOST * aoEnhanceWeight));
    #endif

    // ---- 动态阳光色调混合（仅非末地维度） ----
    #ifndef DIMENSION_THE_END
        float timeBasedTint = saturate(worldSunDir.y * 2.5 - 0.15);
        float tintStrength = AMBIENT_SUNLIGHT_TINT_RATIO * timeBasedTint;
        if (tintStrength > 0.0) {
            vec3 sunColorTint = global.directIlluminance / max(luminance(global.directIlluminance), EPS);
            ambientAccum = mix(ambientAccum, ambientAccum * sunColorTint, tintStrength);
        }
    #endif

    // 应用环境光亮度与颜色控制
    sceneOut += ambientAccum * finalAo * AMBIENT_BRIGHTNESS_MULTIPLIER * AMBIENT_COLOR_TINT;

    // ====== Emissive & Blocklight ======
    #if EMISSIVE_MODE > 0 && defined MC_SPECULAR_MAP
        sceneOut += material.emissiveness * dot(albedo, vec3(0.75));
    #endif
    #if EMISSIVE_MODE < 2
        vec4 emissive = HardCodeEmissive(materialID, albedo, worldPos, blocklightColor);
        #ifndef SSILVB_ENABLED
            if (emissive.a * lightmap.x > EPS) {
                lightmap.x = CalculateBlocklightFalloff(lightmap.x);
                // 体素 GI 开启时：按 VOXEL_GI_BLENDED_LIGHTMAP 屏蔽/混合原版方块光 Lightmap
                #ifdef VOXEL_GI_ENABLED
                    lightmap.x *= VOXEL_GI_BLENDED_LIGHTMAP;
                #endif
                if (lightmap.x > EPS) {
                    sceneOut += lightmap.x * emissive.a * mix(finalAo, vec3(1.0), lightmap.x) * blocklightColor;
                }
            }
        #endif
        sceneOut += emissive.rgb * EMISSIVE_BRIGHTNESS;
    #elif !defined SSILVB_ENABLED
        lightmap.x = CalculateBlocklightFalloff(lightmap.x);
        #ifdef VOXEL_GI_ENABLED
            lightmap.x *= VOXEL_GI_BLENDED_LIGHTMAP;
        #endif
        sceneOut += lightmap.x * mix(finalAo, vec3(1.0), lightmap.x) * blocklightColor;
    #endif

    #ifdef HANDHELD_LIGHTING
        if (heldBlockLightValue + heldBlockLightValue2 > EPS) {
            float attenuation = rcp(1.0 + worldDistSquared) * saturate(dot(worldNormal, -worldDir));
            sceneOut += max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS * attenuation * blocklightColor;
        }
    #endif

    sceneOut += LightningContribution(worldPos, worldNormal);

    #ifdef SSILVB_ENABLED
        #ifndef VOXEL_GI_TRACE  // 与体素 GI 互斥（体素优先）：两者共用 colortex3 信号源，避免重复叠加
            #ifdef SVGF_ENABLED
                vec3 radiance = UpscaleDiffuseIndirect(texelPos, worldNormal, length(viewPos), abs(dot(worldNormal, worldDir)));
            #else
                vec3 radiance = texelFetch(colortex3, texelPos >> 1, 0).rgb;
            #endif
            sceneOut += YCoCgToRGB(radiance);
        #endif
    #endif

    // Final composition
        // ====== 反射获取 ======
    vec4 reflection = vec4(0.0, 0.0, 0.0, FP16_MAX);
    bool isReflective = (material.metalness >= 0.5 || materialID == 10050u);
    bool reflectHit = false;
    if (isReflective) {
        reflection = CalculateSpecularReflections(material, materialID, worldNormal, screenPos, worldDir, viewPos, lightmap.y, dither);
        reflectHit = (reflection.a < FP16_MAX && any(greaterThan(reflection.rgb, vec3(0.0))));
    }

    // ====== 最终合成 ======
    if (reflectHit) {
        // 反射命中：反射与金属自身纹理混合，避免反射完全屏蔽纹理
        // sceneOut 已包含环境光/发光等累积，乘 albedo 即为带光照的纹理底色
        sceneOut = mix(sceneOut * albedo, reflection.rgb, REFLECTION_METAL_MIX);
    } else {
        // 反射未命中或非反射块：标准光照
        // 若为金属但无反射，当作非金属着色，使其获得正常漫反射亮度
        if (material.metalness >= 0.5) {
            material.metalness = 0.0;          // 强制转为非金属
            specularDirect = vec3(0.0);        // 去掉金属高光
        }
        sceneOut *= albedo;
        material.metalness *= 0.2 * lightmap.y + 0.8;
        sceneOut *= oms(material.metalness);
        sceneOut += specularDirect;
        
        // 体素 GI（彩色光源）
        #ifdef VOXEL_GI_ENABLED
            #ifdef DEBUG_VOXEL_RADIANCE
            // 单点诊断：整屏显示"玩家所在体素"（网格坐标恒为 VOXEL_RADIUS）的传播缓存，
            // 逐帧演化 = 时间混合/衰减的直观读数（只回答"缓存是否在衰减"这一个问题）。
            // R = 传播缓存（×100 原始值 ×0.5：nRC≈0.08 → 4 饱和红；≈0.004 → 0.2 暗红）
            // B = alpha（1=空体素；蓝调 = 该空体素已被传播端写入）
            // 注意：查询坐标系 = 相机相对 + VOXEL_RADIUS（与体素化端一致）。
            // 本函数的 worldPos 在 L215 已被改成绝对坐标，此处不能用；
            // 玩家相机自身在网格中的坐标恒为 VOXEL_RADIUS，直接查询即可。
            // 增益 0.15（原 0.5 过早饱和，nRC≥0.02 就纯红，看不出变暗幅度）：
            // nRC≈0.08 → rad.r*0.15≈1.2 近饱和红；≈0.02 → 0.3 暗红；≈0.005 → 0.075 接近黑。
            // 判断标准：小幅抖动=IRC 随机噪声（正常）；持续跌到接近黑=系统性衰减（bug）。
            vec4 rad = FetchVoxelRadiance(ivec3(VOXEL_RADIUS));
            sceneOut = vec3(rad.r * 0.15, 0.0, rad.a * 0.6);
        #else
                // 主 GI = 每像素漫反射追踪（阶段④，对齐 ITRP：Soild_FS 正常模式 GI =
                // colortex1 追踪输出，IRC 仅作内部数据——注入循环 + 追踪命中自反弹种子）。
                // 追踪已迁到 DiffuseIndirect.comp：棋盘半分辨率每帧 1 SPP（1/4 像素），
                // 经 SVGF 时域累积 + 边缘保持滤波后在此读回；此处补乘 albedo×强度，
                // 与旧全分辨率路径（VoxelTracePixel × albedo × STRENGTH）视觉语义一致。
                vec3 voxelGI = vec3(0.0);
                #ifdef VOXEL_GI_TRACE
                    #ifdef SVGF_ENABLED
                        // UpscaleDiffuseIndirect 返回 YCoCg 空间信号（colortex3 全链路 YCoCg），须显式转回 RGB
                        voxelGI = YCoCgToRGB(UpscaleDiffuseIndirect(texelPos, worldNormal, length(viewPos), abs(dot(worldNormal, worldDir))));
                    #else
                        voxelGI = YCoCgToRGB(texelFetch(colortex3, texelPos >> 1, 0).rgb);
                    #endif
                    voxelGI *= albedo * VOXEL_GI_TRACE_STRENGTH;
                #endif
                #ifdef DEBUG_VOXEL_GI
                    // 调试：压暗其余光照，七态区分（用于逐步验证链路）：
                    // 品红 = 发射数据存在（真实自发光光源，如 火把/灯笼）
                    // 青   = 固体体素（voxelData.z>0.5）但无发射/方块光 → 被当普通固体 → 挡光
                    // 黄 = 仅方块光数据存在（非发射光源）
                    // 橙 = 阳光直射面（阴影贴图判定）
                    // 绿 = 接收到 GI 的表面（voxelGI 亮度 > 0.005）
                    // 蓝 = 网格内但光源/阳光/GI 全不满足（查询端≈0）
                    // 红 = dbgCoord 越界（坐标 bug）
                    sceneOut = sceneOut * 0.15;
                    ivec3 dbgCoord = ivec3(camRelPos + cameraPositionFract + float(VOXEL_RADIUS));
                    if (all(greaterThanEqual(dbgCoord, ivec3(0))) && all(lessThan(dbgCoord, ivec3(VOXEL_AREA)))) {
                        vec4 lightData = unpackUnorm4x8(texelFetch(voxelLightSampler, dbgCoord, 0).x);
                        float dbgVoxelID = texelFetch(voxelDataSampler, dbgCoord, 0).z;
                        if (lightData.z > VOXEL_GI_EMISSIVE_THRESHOLD) {  // 新字节序：B=emissive
                            sceneOut = vec3(1.0, 0.0, 1.0);   // 品红：发射数据存在（真实自发光光源）
                        } else if (dbgVoxelID > 0.5 && lightData.y <= 0.1) {  // 新字节序：G=block
                            sceneOut = vec3(0.0, 1.0, 1.0);   // 青：固体但无光（=被当普通固体 → 挡光）
                        } else if (lightData.y > 0.1) {
                            sceneOut = vec3(1.0, 1.0, 0.0);   // 黄：仅方块光数据存在
                        } else if (VoxelPixelSunVisible(camRelPos + cameraPosition)) {
                            sceneOut = vec3(1.0, 0.5, 0.0);   // 橙：真阳光直射面（阴影贴图判定）
                        } else if (luminance(voxelGI) > 0.005) {
                            sceneOut = vec3(0.0, 1.0, 0.0);   // 绿：纯接收 GI
                        } else {
                            sceneOut = vec3(0.0, 0.4, 1.0);   // 蓝：查询端≈0
                        }
                    } else {
                        sceneOut = vec3(1.0, 0.0, 0.0);       // 红：dbgCoord 越界
                    }
                #else
                    sceneOut += voxelGI;
                #endif
            #endif
        #else
            // 体素 GI 未启用（VOXEL_GI_ENABLED 宏未注入本编译单元）：DEBUG 时品红提示
            #ifdef DEBUG_VOXEL_GI
                sceneOut = vec3(1.0, 0.0, 1.0);
            #endif
        #endif
    }
    
}
