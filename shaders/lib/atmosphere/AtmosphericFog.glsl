// 玩家可调参数：体积雾阴影质量 [1, 2, 3]
// 1: 性能模式（隔步采样阴影） | 2: 默认平衡 | 3: 极致（每步采样，原版画质）
#define VF_SHADOW_QUALITY 1 // [1 2 3]

#include "/lib/atmosphere/Rainbow.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

uniform float biomeSandstorm;
uniform float biomeSnowstorm;
uniform float biomeGreenVapor;

//================================================================================================//

// x: Rayleigh y: Mie
const vec2 falloffScale = -1.0 / vec2(32.0, 12.0);

vec2 CalculateFogDensity(in vec3 rayPos, in float uniformFog) {
    rayPos += cameraPosition;

    vec2 density = exp2(abs(rayPos.y - VF_HEIGHT) * oms(step(rayPos.y, VF_HEIGHT) * 0.5) * falloffScale);

#if VF_NOISE_QUALITY == LOW
    rayPos.xz -= vec2(1.0, 0.75) * worldTimeCounter;
    float noise = texture(noisetex, rayPos.xz * 0.002).z;
#elif VF_NOISE_QUALITY == MEDIUM
    vec3 windOffset = vec3(0.07, 0.04, 0.05) * worldTimeCounter;
    rayPos *= 0.03;
    rayPos -= windOffset;

    float noise = Pseudo3DNoise(rayPos) * 2.5;
    noise -= Pseudo3DNoise(rayPos * 4.0 - windOffset);
#endif

    density.y *= sqr(noise) * (2.0 + biomeSandstorm * 8.0 + biomeSnowstorm * 4.0);
    density += uniformFog;

    return density * linearstep(cumulusTopAltitude, cumulusBottomAltitude, rayPos.y);
}

//================================================================================================//

#if !defined CLOUD_SHADOWS || defined PASS_SKY_MAP
    #undef VF_CLOUD_SHADOWS
#endif

mat2x3 RaymarchAtmosphericFog(in vec3 startPos, in vec3 endPos, in float dither, in bool skyMask, in uint steps) {
    float rayLength = sdot(endPos - startPos);
    float norm = inversesqrt(rayLength);
    rayLength *= norm;

    vec3 worldDir = (endPos - startPos) * norm;

    // Adaptive step count
    steps = min(steps, uint(float(steps) * 0.4 + rayLength * rcp(16.0)));

    float maxDist = min(lodRenderDist, 4096.0); 
    if (skyMask) {
        rayLength = clamp((cumulusTopRadius - atmosphereViewHeight) / max0(worldDir.y), 0.0, maxDist);
    }

    float rSteps = rcp(float(steps));
    float stepLength = rayLength * rSteps;
    vec3 rayStep = stepLength * worldDir;
    vec3 rayPos = startPos + rayStep * dither;

    vec3 shadowViewStart = transMAD(shadowModelView, startPos);
    vec3 shadowStart = projMAD(shadowProjection, shadowViewStart);

    vec3 shadowViewStep = mat3(shadowModelView) * rayStep;
    vec3 shadowStep = diagonal3(shadowProjection) * shadowViewStep;
    vec3 shadowPos = shadowStart + shadowStep * dither;

    float LdotV = dot(worldLightDir, worldDir);
    vec2 phase = AtmospherePhase(LdotV);

    float mieDensityMult = VF_MIE_DENSITY * 5e2 * (1.0 + wetness * VF_MIE_DENSITY_RAIN_MULT);
    #ifdef VF_TIME_FADE
        mieDensityMult *= max(wetness, 1.5 - approxSqrt(timeNoon) * 1.5 - timeSunset * 0.75 - timeMidnight * 0.5);
    #endif

    vec3 fogMieExtinction = atmosphere.mieExtinction * mieDensityMult;
    vec3 fogMieScattering = atmosphere.mieScattering * mieDensityMult;

    #ifdef PER_BIOME_FOG
        vec3 biomeAlbedo = mix(vec3(1.0), vec3(1.1, 0.9, 0.7), biomeSandstorm);
        biomeAlbedo = mix(biomeAlbedo, vec3(0.95, 1.1, 1.0), biomeGreenVapor);
        fogMieScattering *= biomeAlbedo;
    #endif

    mat2x3 fogExtinctionCoeff = mat2x3(atmosphere.rayleighScattering * (VF_RAYLEIGH_DENSITY * 16.0), fogMieExtinction);
    mat2x3 fogScatteringCoeff = mat2x3(atmosphere.rayleighScattering * (VF_RAYLEIGH_DENSITY * 16.0), fogMieScattering);

    float uniformFog = (16.0 + wetness * VF_MIE_DENSITY_RAIN_MULT * 16.0) / maxDist;

    vec3 scatteringSun = vec3(0.0);
    vec3 scatteringSky = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    // [优化]：阴影步进缓存设置
    #if VF_SHADOW_QUALITY == 1
        uint shadowSkip = 2u;
    #else
        uint shadowSkip = 1u;
    #endif
    vec3 cachedSampleShadow = vec3(1.0);

    for (uint i = 0u; i < steps; ++i, rayPos += rayStep, shadowPos += shadowStep) {
        vec2 stepDensity = CalculateFogDensity(rayPos, uniformFog);
        if (dot(stepDensity, vec2(1.0)) < EPS) continue; 

    #if defined PASS_VOLUMETRIC_FOG
        // [优化]：根据跳帧间隔采样阴影
        if (i % shadowSkip == 0u) {
            vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;
            if (saturate(shadowScreenPos) == shadowScreenPos) {
                ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
                
                #ifdef COLORED_VOLUMETRIC_FOG
                    float sampleShadowX = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x);
                    float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, shadowTexel, 0).x);
                    if (sampleShadowX != sampleDepth0) {
                        vec3 shadowColorSample = cube(texelFetch(shadowcolor0, shadowTexel, 0).rgb);
                        cachedSampleShadow = shadowColorSample * (sampleShadowX - sampleDepth0) + vec3(sampleDepth0);
                    } else {
                        cachedSampleShadow = vec3(sampleShadowX);
                    }
                #else
                    cachedSampleShadow = vec3(step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x));
                #endif
            } else {
                cachedSampleShadow = vec3(1.0);
            }
        }
        vec3 sampleShadow = cachedSampleShadow;
    #else
        vec3 sampleShadow = vec3(1.0);
    #endif

        #ifdef VF_CLOUD_SHADOWS
            // 云阴影由于频率低，可以常态开启
            vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(rayPos).xy;
            if (saturate(cloudShadowCoord) == cloudShadowCoord) {
                sampleShadow *= texture(cloudShadowTex, cloudShadowCoord).x;
            }
        #endif

        // [优化]：内部透射步数由质量决定
        vec2 opticalDepthSun = vec2(0.0);
        float innerStepSize = 4.0;
        vec3 lightPos = rayPos;
        uint innerSamples = (VF_SHADOW_QUALITY > 1) ? 3u : 1u;
        
        for (uint j = 0u; j < innerSamples; ++j) {
            innerStepSize *= 1.5;
            lightPos += worldLightDir * innerStepSize;
            opticalDepthSun += CalculateFogDensity(lightPos, uniformFog) * innerStepSize;
        }

        vec2 msV = 0.9 * oms(exp2(-8.0 * stepDensity));
        vec2 msEnergy = phase * exp(-opticalDepthSun);
        msEnergy += uniformPhase * msV / (oms(msV) * (1.0 + opticalDepthSun * 0.25));

        vec3 stepExtinction = fogExtinctionCoeff * stepDensity;
        vec3 stepTransmittance = exp(-stepLength * stepExtinction);
        vec3 stepIntegral = transmittance * oms(stepTransmittance) / maxEps(stepExtinction);

        scatteringSun += fogScatteringCoeff * (stepDensity * msEnergy) * stepIntegral * sampleShadow;
        scatteringSky += fogScatteringCoeff * stepDensity * stepIntegral;

        transmittance *= stepTransmittance;

        if (dot(transmittance, vec3(1.0)) < 1e-3) break;
    }

    // 后处理混合与彩虹效果保持原样
    #ifndef VF_CLOUD_SHADOWS
        scatteringSun *= 1.0 - wetness * CLOUD_SHADOW_STRENGTH;
    #endif
    #if !defined PASS_VOLUMETRIC_FOG
        scatteringSun *= eyeSkylightSmooth;
    #endif

    scatteringSky *= eyeSkylightSmooth;

    #ifdef RAINBOWS
        float visibility = wetness * oms(rainStrength);
        if (visibility > EPS) {
            float distanceFade = saturate(rayLength / maxDist) * visibility;
            scatteringSun *= 1.0 + RenderRainbows(LdotV) * distanceFade;
        }
    #endif

    vec3 scattering = scatteringSun * global.directIlluminance;
    scattering += scatteringSky * uniformPhase * global.skyUpIlluminance;

    return mat2x3(scattering, transmittance);
}