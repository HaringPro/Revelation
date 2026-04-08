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

//================================================================================================//

float CloudVolumeOpticalDepth(in vec3 rayPos, in vec3 rayDir, in float noise, in uint steps) {
	float rSteps = 1.0 / float(steps);
	const float rayLength = cumulusThickness * 1.0;

	float stepLength = rayLength * rSteps * rSteps;
	vec3 rayStep = rayDir * stepLength;

	// Early exit if transmittance is too small (optimization)
	float threshold = -log(0.005) / (cumulusExtinction * stepLength);

    float sumDensity = 0.0;
	for (uint i = 0u; i < steps && sumDensity < threshold; ++i) {
		float fi = float(i) + noise;
        vec3 samplePos = rayPos + rayStep * sqr(fi);

		// Normalized height in clouds
		float heightFraction = (length(samplePos) - cumulusBottomRadius) * rcp(cumulusThickness);
		// if (abs(heightFraction - 0.5) > 0.5) break; // Skip if outside the clouds

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
	// https://zhuanlan.zhihu.com/p/457997155
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
		float opticalDepth = density * cloudHighThickness/*  / abs(rayDir.y) */;
		float transmittance = exp2(-rLOG2 * cirrusExtinction * opticalDepth);

		float opticalDepthSun = 0.0; {
			const float rSteps = 1.0 / float(CLOUD_HIGH_SUNLIGHT_SAMPLES);
			const float rayLength = cloudHighThickness * 0.5;
			const float stepLength = rayLength * rSteps * rSteps;

			vec2 rayStep = lightDir.xz * stepLength;

			float sumDensity = 0.0;
			for (uint i = 0u; i < CLOUD_HIGH_SUNLIGHT_SAMPLES; ++i) {
				float fi = float(i) + noise;
				vec2 samplePos = rayPos + rayStep * sqr(fi);

				float density = CloudHighDensity(samplePos);
				sumDensity += density * fi;
			}

			opticalDepthSun = cirrusExtinction * 2.0 * stepLength * sumDensity;
		}

		// Approximate sunlight multi-scattering
		float coarseDensity = approxSqrt(density);
		float scatteringSun = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, coarseDensity, cirrusAlbedo);

		// float opticalDepthSky = density * (cloudHighThickness * 0.5 * cirrusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		// float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));
		float scatteringSky = 1.0 - density;

		vec2 scattering = vec2(scatteringSun, scatteringSky);
		scattering *= oms(transmittance) * cirrusAlbedo;
		return vec3(scattering, transmittance);
	}

	return vec3(0.0, 0.0, 1.0);
}

//================================================================================================//

// Referring to Unreal Engine
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
	// x: sunlight, y: skylight, z: depth, w: transmittance
	vec4 cloudData = vec4(0.0, 0.0, 1e6, 1.0);

	float moonlightFactor = smoothstep(-0.03, -0.05, worldSunDir.y);
    vec3 lightDir = normalize(worldSunDir * oms(2.0 * moonlightFactor));

	float LdotV = dot(lightDir, rayDir);

	// Compute phase function
	#if 0
		float phase = TripleLobePhase(LdotV, cloudForwardG, cloudBackwardG, cloudLobeMixer, cloudSilverG, cloudSilverI);
	#elif 0
		float phase = HgDrainePhase(LdotV, 11.0);
	#else
		float phase = NumericalMieFit(LdotV);
	#endif
	// float phases[cloudMsCount] = SetupParticipatingMediaPhases(phase, cloudMsFalloffC);

	float r = atmosphereViewHeight; // length(atmosphereViewPos)
	float mu = rayDir.y; // dot(atmosphereViewPos, rayDir) / r

	bool planetIntersection = RayIntersectPlanetGround(r, mu);

	//================================================================================================//

	// Low-level clouds
	#ifdef CLOUD_CUMULUS
		if (!((planetIntersection && r < cumulusBottomRadius) || (mu > 0.0 && r > cumulusTopRadius))) {

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, cumulusBottomRadius, cumulusTopRadius);

			// Intersect the volume
			if (intersection.y > 0.0) {
				float rayLength = clamp(intersection.y - intersection.x, 0.0, 5e4);

				float raySteps = float(CLOUD_LOW_SAMPLES_MAX) / 5e4 * rayLength;
				raySteps = round(max(raySteps, float(CLOUD_LOW_SAMPLES_MIN)));

				float stepSize = rayLength * rcp(raySteps);
				float rayT = intersection.x + stepSize * noise.x;

				float sumDist = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				// Raymarch through the cloud volume
				for (uint i = 0u; i < uint(raySteps); ++i, rayT += stepSize) {
					vec3 rayPos = atmosphereViewPos + rayDir * rayT;

					// Normalized height in clouds
					float heightFraction = (length(rayPos) - cumulusBottomRadius) * rcp(cumulusThickness);
					// if (abs(heightFraction - 0.5) > 0.5) break; // Skip if outside the clouds

					// Compute sample cloud density
					float dimensionalProfile;
					float stepDensity = CloudVolumeDensity(rayPos, heightFraction, dimensionalProfile, rayT < 16e3);

					// Skip if no density
					if (stepDensity > cloudEpsilon) {
						// Compute the optical depth of sunlight through clouds
						float opticalDepthSun = CloudVolumeOpticalDepth(rayPos, lightDir, noise.y, CLOUD_LOW_SUNLIGHT_SAMPLES);

						// Approximate sunlight multi-scattering
						float coarseDensity = dimensionalProfile * approxSqrt(stepDensity);
						float scatteringSun = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, coarseDensity, cumulusAlbedo);

						#if CLOUD_CU_SKYLIGHT_SAMPLES > 0
							// Compute the optical depth of skylight through clouds
							float opticalDepthSky = CloudVolumeOpticalDepth(rayPos, vec3(0.0, 1.0, 0.0), noise.y, CLOUD_LOW_SKYLIGHT_SAMPLES) * -rLOG2;

							// See slide 85 of [Schneider, 2017]
							// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
							float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));
						#else
							// Nubis Ambient Scattering Approximation
							float scatteringSky = approxSqrt(1.0 - dimensionalProfile);
							// float scatteringSky = 1.0 - coarseDensity;
						#endif

						// Estimate the light optical depth of the ground from the cloud volume
						float scatteringGround = oms(dimensionalProfile * saturate(heightFraction * 4.0)) * 0.5 * uniformPhase;

						// Compute In-Scatter Probability
						// See slide 92 of [Schneider, 2017]
						#if 0
							float depthProbability = 0.05 + pow(saturate(stepDensity * 8.0), remap(heightFraction, 0.3, 0.85, 0.5, 2.0));
							float verticalProbability = pow(remap(heightFraction, 0.07, 0.14, 0.1, 1.0), 0.75);
							float inScatterProbability = depthProbability * verticalProbability;
							scatteringSun *= inScatterProbability;
						#endif

						vec2 scattering = vec2(scatteringSun + scatteringGround * lightDir.y, scatteringSky);

						float stepOpticalDepth = stepDensity * stepSize;
						float stepTransmittance = exp2(-rLOG2 * cumulusExtinction * stepOpticalDepth);

						// Energy-conserving analytical integration from [Hillaire, 2016]
						float stepIntegral = transmittance * oms(stepTransmittance);
						stepScattering += scattering * stepIntegral;
						transmittance *= stepTransmittance;

						// Method from [Hillaire, 2016]
						// Weighted by stepIntegral instead of transmittance
						sumDist += rayT * stepIntegral;

						// Break if the transmittance is too small (optimization)
						if (transmittance < cloudMinTransmittance) {
							transmittance = 0.0;
							break;
						}
					}
				}

				// Update integral data
				if (transmittance < 1.0) {
					cloudData.xy = stepScattering * cumulusAlbedo;
					cloudData.w = transmittance;
					cloudData.z = sumDist / oms(transmittance);
				}
			}
		}
	#endif

	//================================================================================================//

	// Mid-level clouds
	#ifdef CLOUD_ALTOSTRATUS
		vec2 intersection = RaySphereIntersection(r, mu, cloudMidRadius);

		if (intersection.y > 0.0 && (!planetIntersection || r > cloudMidRadius)) {
			float rayLength = r > cloudMidRadius ? intersection.x : intersection.y;
			vec3 rayPos = rayDir * rayLength + atmosphereViewPos;

			vec3 cloudTemp = RenderCloudMid(rayPos.xz, lightDir, noise.y, phase);

			// Update integral data
			if (cloudTemp.z < 1.0) {
				// Blend layers
				cloudData.xy = mix(cloudData.xy + cloudTemp.xy * cloudData.w, cloudData.xy * cloudTemp.z + cloudTemp.xy, step(cloudMidRadius, r));

				// Update transmittance
				cloudData.w *= cloudTemp.z;

				// Update cloud depth
				cloudData.z = min(rayLength, cloudData.z);
			}
		}
	#endif

	// High-level clouds
	#if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		vec2 intersection = RaySphereIntersection(r, mu, cloudHighRadius);

		if (intersection.y > 0.0 && (!planetIntersection || r > cloudHighRadius)) {
			float rayLength = r > cloudHighRadius ? intersection.x : intersection.y;
			vec3 rayPos = rayDir * rayLength + atmosphereViewPos;

			vec3 cloudTemp = RenderCloudHigh(rayPos.xz, lightDir, noise.y, phase);

			// Update integral data
			if (cloudTemp.z < 1.0) {
				// Blend layers
				cloudData.xy = mix(cloudData.xy + cloudTemp.xy * cloudData.w, cloudData.xy * cloudTemp.z + cloudTemp.xy, step(cloudHighRadius, r));

				// Update transmittance
				cloudData.w *= cloudTemp.z;

				// Update cloud depth
				cloudData.z = min(rayLength, cloudData.z);
			}
		}
	#endif

    return cloudData;
}

void CompositeClouds(inout vec3 skyRadiance, in vec4 cloudData, in vec3 rayDir) {
	// x: sunlight, y: skylight, z: depth, w: transmittance
	if (cloudData.w < 1.0) {
		vec3 cloudPos = atmosphereViewPos + rayDir * cloudData.z;

		// Compute illumination to clouds
        vec3 sunIlluminance = sunIrradiance * AtmosphereTransmittanceToSun(cloudPos, worldSunDir);
        vec3 moonIlluminance = sunIrradiance * AtmosphereTransmittanceToSun(cloudPos, -worldSunDir) * moonlightMult;
		vec3 directIlluminance = 128.0 * (sunIlluminance + moonIlluminance);

		// Normalized height in clouds
		float heightFraction = saturate((length(cloudPos) - cumulusBottomRadius) * rcp(cumulusThickness));
		vec3 skyIlluminance = mix(ReconstructSH3(global.skySH, vec3(0.0, -1.0, 0.0)), global.skyUpIlluminance, heightFraction);

		vec3 scattering = cloudData.x * directIlluminance;
		scattering += cloudData.y * rPI * skyIlluminance;

		scattering += LightningContribution(cloudPos - atmosphereViewPos) * sqr(cloudData.y);

		// Aerial perspective
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
		skyRadiance = skyRadiance * oms(oms(cloudData.w) * aerialT) + scattering * aerialT;
	}
}
