/*
--------------------------------------------------------------------------------

	References:
		[Schneider, 2015] Andrew Schneider. “The Real-Time Volumetric Cloudscapes Of Horizon: Zero Dawn”. SIGGRAPH 2015.
			https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn
		[Schneider, 2016] Andrew Schneider. "GPU Pro 7: Real Time Volumetric Cloudscapes". p.p. (97-128) CRC Press, 2016.
			https://www.taylorfrancis.com/chapters/edit/10.1201/b21261-11/real-time-volumetric-cloudscapes-andrew-schneider
		[Schneider, 2017] Andrew Schneider. "Nubis: Authoring Realtime Volumetric Cloudscapes with the Decima Engine". SIGGRAPH 2017.
			https://advances.realtimerendering.com/s2017/Nubis%20-%20Authoring%20Realtime%20Volumetric%20Cloudscapes%20with%20the%20Decima%20Engine%20-%20Final.pptx
		[Schneider, 2022] Andrew Schneider. "Nubis, Evolved: Real-Time Volumetric Clouds for Skies, Environments, and VFX". SIGGRAPH 2022.
			https://advances.realtimerendering.com/s2022/SIGGRAPH2022-Advances-NubisEvolved-NoVideos.pdf
		[Schneider, 2023] Andrew Schneider. "Nubis Cubed: Methods (and madness) to model and render immersive real-time voxel-based clouds". SIGGRAPH 2023.
			https://advances.realtimerendering.com/s2023/Nubis%20Cubed%20(Advances%202023).pdf
		[Hillaire, 2016] Sebastien Hillaire. “Physically based Sky, Atmosphere and Cloud Rendering”. SIGGRAPH 2016.
			https://blog.selfshadow.com/publications/s2016-shading-course/
			https://www.ea.com/frostbite/news/physically-based-sky-atmosphere-and-cloud-rendering
		[Högfeldt, 2016] Rurik Högfeldt. "Convincing Cloud Rendering: An Implementation of Real-Time Dynamic Volumetric Clouds in Frostbite". Department of Computer Science and Engineering, Gothenburg, Sweden, 2016.
			https://publications.lib.chalmers.se/records/fulltext/241770/241770.pdf
		[Bauer, 2019] Fabian Bauer. "Creating the Atmospheric World of Red Dead Redemption 2: A Complete and Integrated Solution". SIGGRAPH 2019.
			https://www.advances.realtimerendering.com/s2019/slides_public_release.pptx
		[Wrenninge et al., 2013] Magnus Wrenninge, Chris Kulla, Viktor Lundqvist. “Oz: The Great and Volumetric”. SIGGRAPH 2013 Talks.
			https://dl.acm.org/doi/10.1145/2504459.2504518

--------------------------------------------------------------------------------
*/

#include "/lib/atmosphere/clouds/Shape.glsl"
#include "/lib/atmosphere/clouds/PhaseLut.glsl"

//================================================================================================//

// Referring to Unreal Engine
// For Wrenninge MS
float[cloudMsCount] SetupParticipatingMediaPhases(float primaryPhase, float falloff) {
	float phases[cloudMsCount];
	phases[0] = primaryPhase;

	for (uint ms = 1u; ms < cloudMsCount; ++ms) {
		phases[ms] = mix(uniformPhase, primaryPhase, falloff);
		falloff *= falloff;
	}

	return phases;
}

float CloudVolumeOpticalDepth(vec3 rayPos, vec3 rayDir, float noise) {
	const uint steps = uint(CLOUD_LOW_SUNLIGHT_SAMPLES);
	const float rSteps = 1.0 / float(steps);
	float rayLength = cloudLayer0.thickness * (1.75 - rayDir.y);

	float stepLength = rayLength * rSteps * rSteps;
	vec3 rayStep = rayDir * stepLength;

	// Early exit if transmittance is too small (optimization)
	float threshold = -log(0.005) / (cloudLayer0.coeff.extinction * stepLength);

	float sumDensity = 0.0;
	for (uint i = 0u; i < steps && sumDensity < threshold; ++i) {
		float fi = float(i);
		vec3 samplePos = rayPos + rayStep * sqr(fi + noise);

		// Normalized height in clouds
		float heightFraction = length(samplePos) * rcp(cloudLayer0.thickness) - cloudLayer0.minHeight / cloudLayer0.thickness;
		// if (abs(heightFraction - 0.5) > 0.5) break; // Skip if outside the clouds

		float temp;
		uint sampleMode = i < 3u ? cloudDensityModeDetail : cloudDensityModeBase;
		float density = CloudVolumeDensity(samplePos, heightFraction, temp, sampleMode);
		sumDensity += density * (fi + 0.5);
	}

	return cloudLayer0.coeff.extinction * 2.0 * stepLength * sumDensity;
}

// [Wrenninge et al., 2013]
float CloudMultiScatteringApproxOz(float opticalDepth, float phase) {
	float scatteringFalloff = cloudMsFalloffA;
	float extinctionFalloff = cloudMsFalloffB;

	float scattering = exp2(-rLOG2 * opticalDepth) * phase;

	for (uint ms = 1u; ms < cloudMsCount; ++ms) {
		phase = mix(uniformPhase, phase, cloudMsFalloffC);

		float transmittance = exp2(-rLOG2 * extinctionFalloff * opticalDepth);
		scattering += transmittance * phase * scatteringFalloff;

		scatteringFalloff *= scatteringFalloff;
		extinctionFalloff *= extinctionFalloff;
	}

	return scattering;
}

vec2 CloudMultiScatteringApproxHaringPro(float sunlightOD, float phase, float sigmaT, float omega, float msVolume, vec3 lightDir) {
	// https://zhuanlan.zhihu.com/p/457997155
	float fms = omega * oms(exp2(-256.0 * sigmaT));

    float scatteringSun = phase + uniformPhase * fms / (1.0 - fms);
    scatteringSun *= exp(-sunlightOD);
    scatteringSun += msVolume / (1.0 + sunlightOD * 0.5);

    // Estimate the transmittance to the zenith using sunlight optical depth
    float skylightOD = sunlightOD * (lightDir.y + 0.05); // Multiply by sin(elevation angle) to convert to the zenith OD
    float scatteringSky = 1.0 / (1.0 + skylightOD); // 1 / (1 + x) curve to approximate MS

	return vec2(scatteringSun, scatteringSky);
}

//================================================================================================//

vec3 RenderCloudHigh(vec3 rayPos, vec3 lightDir, float noise, float LdotV) {
	float density = CloudHighDensity(rayPos.xz);
	if (density > EPS) {
		float sigmaT = density * cloudLayer2.coeff.extinction;
		float transmittance = exp2(-rLOG2 * sigmaT * cloudLayer2.thickness);

        // Raymarch optical depth to sun
        const uint steps = 3;
        const float rSteps = 1.0 / float(steps);
        float rayLength = cloudLayer2.thickness * (1.5 - lightDir.y);
        float stepLength = rayLength * rSteps * rSteps;

        vec2 rayStep = lightDir.xz * stepLength;

        float sumDensity = 0.0;
        for (uint i = 0u; i < steps; ++i) {
            float fi = float(i);
            vec2 samplePos = rayPos.xz + rayStep * sqr(fi + noise);

            float density = CloudHighDensity(samplePos);
            sumDensity += density * (fi + 0.5);
        }

        float opticalDepthSun = cloudLayer2.coeff.extinction * 2.0 * stepLength * sumDensity;

		// Approximate multi-scattering
		float phase = SampleCloudPhaseLutScalar(LdotV, CLOUD_PHASE_CI);
		vec2 scattering = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, sigmaT, cloudLayer2.coeff.albedo, density + 0.25, lightDir);

		scattering *= oms(transmittance) * cloudLayer2.coeff.albedo;
		return vec3(scattering, transmittance);
	}

	return vec3(0.0, 0.0, 1.0);
}

//================================================================================================//

CloudRenderResult RenderClouds(vec3 rayDir, vec2 noise, vec3 skyRadiance) {
    CloudRenderResult result = CloudRenderResult(vec3(0.0), 1.0, 1e6);

	// x: sunlight, y: skylight
	vec2 scatteringBase = vec2(0.0);

	float moonlightFactor = smoothstep(-0.03, -0.05, sunDirWorld.y);
	vec3 lightDir = normalize(sunDirWorld * oms(2.0 * moonlightFactor));

	float LdotV = dot(lightDir, rayDir);

	float r = atmosphereViewHeight; // length(atmosphereViewPos)
	float mu = rayDir.y; // dot(atmosphereViewPos, rayDir) / r

	// Compute phase function
	float phase = SampleCloudPhaseLutScalar(LdotV, CLOUD_PHASE_CU);

	bool planetIntersection = RayIntersectPlanetGround(r, mu);

	//================================================================================================//

	// Low-level clouds
	#ifdef CLOUD_CU
		if (!((planetIntersection && r < cloudLayer0.minHeight) || (mu > 0.0 && r > cloudLayer0.maxHeight))) {

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, cloudLayer0.minHeight, cloudLayer0.maxHeight);

			// Intersect the volume
			if (intersection.y > 0.0) {
                const float maxRaymarchingDist = 5e4;
				float tMax = clamp(intersection.y - intersection.x, 0.0, maxRaymarchingDist);

                // Variable step count based on raymarching distance
                float stepCount = floor(mix(
                    CLOUD_LOW_SAMPLES_MIN,
                    CLOUD_LOW_SAMPLES_MAX,
                    saturate(tMax * rcp(maxRaymarchingDist))
                ));
                float invStepCount = rcp(stepCount);
				float stepLength = tMax * invStepCount;

				vec3 startPos = atmosphereViewPos + rayDir * intersection.x;

				float sumDist = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;
				#ifdef CLOUD_EMPTY_SPACE_SKIP
                    bool fineSampling = true;
                    uint emptySampleCount = 0u;
                    const uint emptySampleLimit = 4u;
                    const float maxCoarseSpan = cloudLayer0.thickness * 0.125;
                    bool allowCoarseStride = stepLength <= maxCoarseSpan;
				#endif

				// Raymarch through the cloud volume
				for (int i = 0; i < int(stepCount); ++i) {
					float t = (float(i) + noise.x) * stepLength;

					vec3 rayPos = startPos + rayDir * t;

					// Normalized height in clouds
					float heightFraction = length(rayPos) * rcp(cloudLayer0.thickness) - cloudLayer0.minHeight / cloudLayer0.thickness;
					// if (abs(heightFraction - 0.5) > 0.5) break; // Skip if outside the clouds

					#ifdef CLOUD_EMPTY_SPACE_SKIP
					if (!fineSampling) {
						float dimensionalProfile;
						CloudVolumeDensity(
							rayPos,
							heightFraction,
							dimensionalProfile,
							cloudDensityModeCoarse
						);
						if (dimensionalProfile < cloudProfileEpsilon) {
							if (allowCoarseStride) i++;
							continue;
						}

						fineSampling = true;
						emptySampleCount = 0u;
						i = max(i - 2, -1);
						continue;
					}
					#endif

					// Compute sample cloud density
					float dimensionalProfile;
					float stepDensity = CloudVolumeDensity(
						rayPos,
						heightFraction,
						dimensionalProfile,
						cloudDensityModeDetail
					);

					#ifdef CLOUD_EMPTY_SPACE_SKIP
					if (stepDensity < cloudDensityEpsilon) {
						if (++emptySampleCount >= emptySampleLimit) {
							fineSampling = false;
							emptySampleCount = 0u;
						}
						continue;
					}
					emptySampleCount = 0u;
					#endif

					// Skip if no density
					if (stepDensity >= cloudDensityEpsilon) {
						float sigmaT = stepDensity * cloudLayer0.coeff.extinction;

						// Compute the optical depth of sunlight through clouds
						float opticalDepthSun = CloudVolumeOpticalDepth(rayPos, lightDir, noise.y);

						// Approximate multi-scattering
                        float msVolume = linearstep(0.25, 1.0, dimensionalProfile);
                        msVolume *= linearstep(0.0, 0.4, heightFraction);
						vec2 scattering = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, sigmaT, cloudLayer0.coeff.albedo, msVolume, lightDir);

						// Estimate the ground reflected light
						float groundT = rcp(1.0 + sigmaT * heightFraction * cloudLayer0.thickness);
						scattering += groundT * uniformPhase * lightDir.y;

						float stepTransmittance = exp2(-rLOG2 * sigmaT * stepLength);

						// Energy-conserving analytical integration from [Hillaire, 2016]
						float stepIntegral = transmittance * oms(stepTransmittance);
						stepScattering += scattering * stepIntegral;
						transmittance *= stepTransmittance;

						// Method from [Hillaire, 2016]
						// Weighted by stepIntegral instead of transmittance
						sumDist += (t + intersection.x) * stepIntegral;

						// Break if the transmittance is too small (optimization)
						if (transmittance < cloudMinTransmittance) {
							transmittance = 0.0;
							break;
						}
					}
				}

				// Update integral data
				if (lessThanFLT1(transmittance)) {
					scatteringBase = stepScattering * cloudLayer0.coeff.albedo;
					result.transmittance = transmittance;
					result.frontDepth = sumDist / oms(transmittance);
				}
			}
		}
	#endif

	//================================================================================================//

	// Mid-level clouds
    // TODO: Implement

	// High-level clouds
	#if defined CLOUD_CC || defined CLOUD_CS || defined CLOUD_CI
		vec2 intersection = RaySphereIntersection(r, mu, cloudLayer2.minHeight);

		if (intersection.y > 0.0 && (!planetIntersection || r > cloudLayer2.minHeight)) {
			float rayLength = r > cloudLayer2.minHeight ? intersection.x : intersection.y;
			vec3 rayPos = rayDir * rayLength + atmosphereViewPos;

			vec3 cloudTemp = RenderCloudHigh(rayPos, lightDir, noise.y, LdotV);

			// Update integral data
			if (lessThanFLT1(cloudTemp.z)) {
				// Blend layers
				scatteringBase = mix(scatteringBase + cloudTemp.xy * result.transmittance, scatteringBase * cloudTemp.z + cloudTemp.xy, step(cloudLayer2.minHeight, r));

				// Update transmittance
				result.transmittance *= cloudTemp.z;

				// Update cloud depth
				result.frontDepth = min(rayLength, result.frontDepth);
			}
		}
	#endif

	if (lessThanFLT1(result.transmittance)) {
		vec3 cloudPos = atmosphereViewPos + rayDir * result.frontDepth;

		// Compute illumination to clouds
		vec3 sunIlluminance = sunIrradiance * AtmosphereTransmittanceToSun(cloudPos, sunDirWorld);
		vec3 moonIlluminance = moonIrradiance * AtmosphereTransmittanceToSun(cloudPos, moonDirWorld);
		vec3 directIlluminance = sunIlluminance + moonIlluminance;

		// Lerp bottom and top sky illuminance based on normalized height
		// float heightFraction = saturate((length(cloudPos) - cloudLayer0.minHeight) * rcp(cloudLayer0.thickness));
        // vec3 skyBottomIlluminance = ConvolvedReconstructSH3(global.skySH, vec3(0.0, -1.0, 0.0));
		// vec3 skyIlluminance = mix(skyBottomIlluminance, global.skyUpIlluminance, heightFraction);

		result.scatteredLight = scatteringBase.x * directIlluminance;
		result.scatteredLight += scatteringBase.y * global.skyUpIlluminance;

		result.scatteredLight += LightningContribution(cloudPos - atmosphereViewPos) * sqr(scatteringBase.y);

		// Aerial perspective
		vec3 aerialT = AtmosphereTransmittanceToPoint(atmosphereViewPos, rayDir, result.frontDepth);
		result.scatteredLight = mix(skyRadiance * oms(result.transmittance), result.scatteredLight, aerialT);
	}

	return result;
}
