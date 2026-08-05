/*
--------------------------------------------------------------------------------

    References:
        [Schneider, 2015] … (同前)
        [Wrenninge et al., 2013] …

--------------------------------------------------------------------------------
*/

#include "/lib/atmosphere/clouds/Shape.glsl"

//================================================================================================//

// 低层云光学深度：保持原版循环积分，保证平滑无硬边
float CloudVolumeOpticalDepth(in vec3 rayPos, in vec3 rayDir, in float noise, in uint steps) {
    float rSteps = 1.0 / float(steps);
    const float rayLength = cumulusThickness * 1.0;

    float stepLength = rayLength * rSteps * rSteps;
    vec3 rayStep = rayDir * stepLength;

    // Precomputed -log(0.005) ≈ 5.298317
    float threshold = 5.298317 / (cumulusExtinction * stepLength);
    float invThickness = rcp(cumulusThickness);

    float sumDensity = 0.0;
    float fi = noise;
    
    for (uint i = 0u; i < steps && sumDensity < threshold; ++i, fi += 1.0) {
        vec3 samplePos = rayPos + rayStep * sqr(fi);

        // Normalized height inside the cloud shell
        float heightFraction = (length(samplePos) - cumulusBottomRadius) * invThickness;

        float temp;
        float density = CloudVolumeDensity(samplePos, heightFraction, temp, i < 3u);
        sumDensity += density * fi;
    }

    return cumulusExtinction * 2.0 * stepLength * sumDensity;
}

// [Wrenninge et al., 2013]
float CloudMultiScatteringApproxOz(in float opticalDepth, in float phase) {
    float scatteringFalloff = cloudMsFalloffA;
    float extinctionFalloff = cloudMsFalloffB;

    float single = exp2(-rLOG2 * opticalDepth) * phase;
    float multiple = 0.0;

    for (uint ms = 1u; ms < cloudMsCount; ++ms) {
        phase = mix(uniformPhase, phase, cloudMsFalloffC);

        float transmittance = exp2(-rLOG2 * extinctionFalloff * opticalDepth);
        multiple += transmittance * phase * scatteringFalloff;

        scatteringFalloff *= scatteringFalloff;
        extinctionFalloff *= extinctionFalloff;
    }

    return single + multiple;
}

float CloudMultiScatteringApproxHaringPro(in float opticalDepth, in float phase, in float extinction, in float albedo) {
    float msV = albedo * oms(approxExp(-8.0 * extinction));
    float msEnergy = msV / (1.0 - msV) * exp2(-0.25 * opticalDepth);

    float single = exp2(-rLOG2 * opticalDepth) * phase;
    return single + msEnergy * mix(phase, uniformPhase, msV);
}

//================================================================================================//

vec3 RenderCloudMid(in vec2 rayPos, in vec3 rayDir, in float noise, in float phase) {
    return vec3(0.0, 0.0, 1.0);
}

//================================================================================================//

vec3 RenderCloudHigh(in vec2 rayPos, in vec3 lightDir, in float noise, in float phase) {
    float density = CloudHighDensity(rayPos);
    if (density > EPS) {
        float opticalDepth = density * cloudHighThickness;
        float transmittance = exp2(-rLOG2 * cirrusExtinction * opticalDepth);

        // 固定极淡强度，不依赖光照方向
        float scatteringStrength = 0.15;
        vec2 scattering = vec2(scatteringStrength);

        scattering *= oms(transmittance) * cirrusAlbedo;
        return vec3(scattering, transmittance);
    }
    return vec3(0.0, 0.0, 1.0);
}

//================================================================================================//

float[cloudMsCount] SetupParticipatingMediaPhases(in float primaryPhase, in float falloff) {
    float phases[cloudMsCount];
    phases[0] = primaryPhase;

    for (uint ms = 1u; ms < cloudMsCount; ++ms) {
        phases[ms] = mix(uniformPhase, primaryPhase, falloff);
        falloff *= falloff;
    }
    return phases;
}

vec4 RenderClouds(in vec3 rayDir, in vec2 noise) {
    // 末地和地狱不渲染任何云
    #if defined(DIMENSION_THE_END) || defined(DIMENSION_NETHER)
        return vec4(0.0, 0.0, 1e6, 1.0);
    #endif

    vec4 cloudData = vec4(0.0, 0.0, 1e6, 1.0);

    float moonlightFactor = smoothstep(-0.03, -0.05, worldSunDir.y);
    vec3 lightDir = normalize(worldSunDir * oms(2.0 * moonlightFactor));
    float LdotV = dot(lightDir, rayDir);

    #if 0
        float phase = TripleLobePhase(LdotV, cloudForwardG, cloudBackwardG, cloudLobeMixer, cloudSilverG, cloudSilverI);
    #elif 0
        float phase = HgDrainePhase(LdotV, 11.0);
    #else
        float phase = NumericalMieFit(LdotV);
    #endif

    float r = atmosphereViewHeight;
    float mu = rayDir.y;
    bool planetIntersection = RayIntersectPlanetGround(r, mu);

    const float cumulusBottomRadiusLocal = cumulusBottomRadius;
    const float cumulusTopRadiusLocal = cumulusTopRadius;
    const float cumulusThicknessLocal = cumulusThickness;
    const float invCumulusThickness = 1.0 / cumulusThicknessLocal;
    const float cumulusExtinctionLocal = cumulusExtinction;

    //================================================================================================//
    // Low-level clouds
    #ifdef CLOUD_CUMULUS
        if (!((planetIntersection && r < cumulusBottomRadiusLocal) || (mu > 0.0 && r > cumulusTopRadiusLocal))) {
            vec2 intersection = RaySphericalShellIntersection(r, mu, cumulusBottomRadiusLocal, cumulusTopRadiusLocal);

            if (intersection.y > 0.0) {
                float rayLength = clamp(intersection.y - intersection.x, 0.0, 5e4);
                
                float raySteps = round(max(float(CLOUD_LOW_SAMPLES_MAX) * 2e-5 * rayLength, float(CLOUD_LOW_SAMPLES_MIN)));
                float stepSize = rayLength * rcp(raySteps);
                float rayT = intersection.x + stepSize * noise.x;

                vec2 stepScattering = vec2(0.0);
                float transmittance = 1.0;
                float sumDist = 0.0;

                float stepExtPhase = -rLOG2 * cumulusExtinctionLocal * stepSize; 

                for (uint i = 0u; i < uint(raySteps); ++i, rayT += stepSize) {
                    vec3 rayPos = atmosphereViewPos + rayDir * rayT;

                    float heightFraction = (length(rayPos) - cumulusBottomRadiusLocal) * invCumulusThickness;
                    
                    float dimensionalProfile;
                    float stepDensity = CloudVolumeDensity(rayPos, heightFraction, dimensionalProfile, rayT < 16e3);

                    if (stepDensity > cloudEpsilon) {
                        float opticalDepthSun = CloudVolumeOpticalDepth(rayPos, lightDir, noise.y, CLOUD_LOW_SUNLIGHT_SAMPLES);
                        float coarseDensity = dimensionalProfile * approxSqrt(stepDensity);
                        float scatteringSun = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, coarseDensity, cumulusAlbedo);

                        #if CLOUD_CU_SKYLIGHT_SAMPLES > 0
                            float opticalDepthSky = CloudVolumeOpticalDepth(rayPos, vec3(0.0, 1.0, 0.0), noise.y, CLOUD_LOW_SKYLIGHT_SAMPLES) * -rLOG2;
                            float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));
                        #else
                            float scatteringSky = approxSqrt(1.0 - dimensionalProfile);
                        #endif

                        float scatteringGround = oms(dimensionalProfile * saturate(heightFraction * 4.0)) * 0.5 * uniformPhase;
                        vec2 scattering = vec2(scatteringSun + scatteringGround * lightDir.y, scatteringSky);

                        float stepTransmittance = exp2(stepExtPhase * stepDensity); 
                        float stepIntegral = transmittance * oms(stepTransmittance);
                        
                        stepScattering += scattering * stepIntegral;
                        transmittance *= stepTransmittance;
                        sumDist += rayT * stepIntegral;

                        if (transmittance < cloudMinTransmittance) {
                            transmittance = 0.0;
                            break;
                        }
                    }
                }

                if (transmittance < 1.0) {
                    cloudData.xy = stepScattering * cumulusAlbedo;
                    cloudData.w = transmittance;
                    cloudData.z = sumDist / oms(transmittance);
                }
            }
        }
    #endif

    //================================================================================================//
    if (cloudData.w < cloudMinTransmittance) return cloudData;

    // Mid-level clouds
    #ifdef CLOUD_ALTOSTRATUS
        vec2 intersectionMid = RaySphereIntersection(r, mu, cloudMidRadius);

        if (intersectionMid.y > 0.0 && (!planetIntersection || r > cloudMidRadius)) {
            float rayLength = r > cloudMidRadius ? intersectionMid.x : intersectionMid.y;
            vec3 rayPos = rayDir * rayLength + atmosphereViewPos;

            vec3 cloudTemp = RenderCloudMid(rayPos.xz, lightDir, noise.y, phase);

            if (cloudTemp.z < 1.0) {
                float blend = step(cloudMidRadius, r);
                cloudData.xy = mix(cloudData.xy + cloudTemp.xy * cloudData.w, cloudData.xy * cloudTemp.z + cloudTemp.xy, blend);
                cloudData.w *= cloudTemp.z;
                cloudData.z = min(rayLength, cloudData.z);
            }
        }
    #endif

    if (cloudData.w < cloudMinTransmittance) return cloudData;

    // High-level clouds
    #if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
        vec2 intersectionHigh = RaySphereIntersection(r, mu, cloudHighRadius);

        if (intersectionHigh.y > 0.0 && (!planetIntersection || r > cloudHighRadius)) {
            float rayLength = r > cloudHighRadius ? intersectionHigh.x : intersectionHigh.y;
            vec3 rayPos = rayDir * rayLength + atmosphereViewPos;

            vec3 cloudTemp = RenderCloudHigh(rayPos.xz, lightDir, noise.y, phase);

            if (cloudTemp.z < 1.0) {
                float blend = step(cloudHighRadius, r);
                cloudData.xy = mix(cloudData.xy + cloudTemp.xy * cloudData.w, cloudData.xy * cloudTemp.z + cloudTemp.xy, blend);
                cloudData.w *= cloudTemp.z;
                cloudData.z = min(rayLength, cloudData.z);
            }
        }
    #endif

    return cloudData;
}

void CompositeClouds(inout vec3 skyRadiance, in vec4 cloudData, in vec3 rayDir) {
    // 末地和地狱不混合云
    #if defined(DIMENSION_THE_END) || defined(DIMENSION_NETHER)
        return;
    #endif

    if (cloudData.w < 1.0) {
        vec3 cloudPos = atmosphereViewPos + rayDir * cloudData.z;

        vec3 sunIlluminance = sunIrradiance * AtmosphereTransmittanceToSun(cloudPos, worldSunDir);
        vec3 moonIlluminance = sunIrradiance * AtmosphereTransmittanceToSun(cloudPos, -worldSunDir) * moonlightMult;
        vec3 directIlluminance = 128.0 * (sunIlluminance + moonIlluminance);

        float heightFraction = saturate((length(cloudPos) - cumulusBottomRadius) * rcp(cumulusThickness));
        vec3 skyIlluminance = mix(ReconstructSH3(global.skySH, vec3(0.0, -1.0, 0.0)), global.skyUpIlluminance, heightFraction);

        vec3 scattering = cloudData.x * directIlluminance;
        scattering += cloudData.y * rPI * skyIlluminance;
        scattering += LightningContribution(cloudPos - atmosphereViewPos) * sqr(cloudData.y);

        vec3 aerialT;
        if (sdot(atmosphereViewPos) < sdot(cloudPos)) {
            vec3 t1 = AtmosphereTransmittanceToPoint(atmosphereViewPos, rayDir);
            vec3 t2 = AtmosphereTransmittanceToPoint(cloudPos, rayDir);
            aerialT = saturate(t1 / t2);
        } else {
            vec3 t1 = AtmosphereTransmittanceToPoint(atmosphereViewPos, -rayDir);
            vec3 t2 = AtmosphereTransmittanceToPoint(cloudPos, -rayDir);
            aerialT = saturate(t2 / t1);
        }
        
        skyRadiance = skyRadiance * (1.0 - (1.0 - cloudData.w) * aerialT) + scattering * aerialT;
    }
}