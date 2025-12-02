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

    float sumDensity = 0.0;
	for (uint i = 0u; i < steps; ++i) {
		float fi = float(i) + noise;
        vec3 samplePos = rayPos + rayStep * sqr(fi);

		float temp;
		float density = CloudVolumeDensity(samplePos, temp, temp, i < 2u);
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
	float msV = albedo * oms(exp2(-8.0 * extinction));
	float msT = 0.2 / (1.0 + 0.2 * opticalDepth);

	float transmittance = exp2(-rLOG2 * opticalDepth);
	return transmittance * phase + msT * msV / oms(msV) * uniformPhase;
}

//================================================================================================//

vec3 RenderCloudMid(in vec2 rayPos, in vec3 rayDir, in float noise, in float phase) {
	return vec3(0.0);
}

//================================================================================================//

vec3 RenderCloudHigh(in vec2 rayPos, in vec3 rayDir, in float noise, in float phase) {
	float density = CloudHighDensity(rayPos);
	if (density > EPS) {
		float opticalDepth = density * cloudHighThickness/*  / abs(rayDir.y) */;
		float integral = oms(exp2(-rLOG2 * cirrusExtinction * opticalDepth));

		float opticalDepthSun = 0.0; {
			const float rSteps = 1.0 / float(CLOUD_HIGH_SUNLIGHT_SAMPLES);
			const float rayLength = cloudHighThickness * 1.0;
			const float stepLength = rayLength * rSteps * rSteps;

			vec2 rayStep = worldLightVector.xz * stepLength;

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
		float coarseDensity = density * (2.0 - density) + 0.1;
		float scatteringSun = CloudMultiScatteringApproxHaringPro(opticalDepthSun, phase, coarseDensity, cirrusAlbedo);

		// float opticalDepthSky = density * (cloudHighThickness * 0.5 * cirrusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		// float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));
		float scatteringSky = approxSqrt(1.0 - density);

		// Compute powder effect
		// Formula from [Schneider, 2015]
		// float powder = 2.0 * oms(exp2(-(density * 32.0 + 0.1)));

		// TODO: Better implementation
		// float inScatterProbability = oms(exp2(-density * 16.0 - 0.25)) * hPI;

		scatteringSun *= integral * cirrusAlbedo;
		scatteringSky *= integral * cirrusAlbedo;
		return vec3(scatteringSun, scatteringSky, integral);
	} else {
		return vec3(0.0);
	}
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

vec4 RenderClouds(in vec3 rayDir, in vec2 noise, out float cloudDepth) {
	float moonlightFactor = smoothstep(-0.03, -0.05, worldSunVector.y);
    vec3 lightDir = worldSunVector * oms(2.0 * moonlightFactor);

	float LdotV = dot(lightDir, rayDir);

	// Compute phases for clouds' sunlight multi-scattering
	#if 0
		float phase = TripleLobePhase(LdotV, cloudForwardG, cloudBackwardG, cloudLobeMixer, cloudSilverG, cloudSilverI);
	#elif 1
		float phase = HgDrainePhase(LdotV, 11.0);
	#else
		float phase = NumericalMieFit(LdotV);
	#endif
	// float phases[cloudMsCount] = SetupParticipatingMediaPhases(phase, cloudMsFalloffC);

	vec3 camera = vec3(0.0, viewerHeight, 0.0);
	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	bool planetIntersection = RayIntersectsGround(r, mu);

	// Initialize
	vec2 integralScattering = vec2(0.0);
	float cloudTransmittance = 1.0;
	cloudDepth = 128e3;

	//================================================================================================//

	// Low-level clouds
	#ifdef CLOUD_CUMULUS
		if (!((planetIntersection && r < cumulusBottomRadius) || (mu > 0.0 && r > cumulusTopRadius))) {

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, cumulusBottomRadius, cumulusTopRadius);

			// Intersect the volume
			if (intersection.y > 0.0) {
				float withinVolumeSmooth = linearstep(cumulusThickness + 32.0, cumulusThickness - 64.0, abs(r * 2.0 - (cumulusBottomRadius + cumulusTopRadius)));

				float rayLength = clamp(intersection.y - intersection.x, 0.0, 1e5 - withinVolumeSmooth * 6e4);

				#if defined PASS_SKY_MAP
					uint raySteps = CLOUD_LOW_SAMPLES >> 1u;
					// Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * oms(abs(mu) * 0.5));
				#else
					uint raySteps = CLOUD_LOW_SAMPLES;
					// Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * mix(oms(abs(mu) * 0.5), 4.0, withinVolumeSmooth));
				#endif

				float stepSize = rayLength * rcp(float(raySteps));
				float rayT = intersection.x + stepSize * noise.x;

				float rayLengthWeighted = 0.0;
				float raySumWeight = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				// Raymarch through the cloud volume
				for (uint i = 0u; i < raySteps; ++i, rayT += stepSize) {
					vec3 rayPos = camera + rayDir * rayT;

					// Method from [Hillaire, 2016]
					// Accumulate the weighted ray length
					rayLengthWeighted += rayT * transmittance;
					raySumWeight += transmittance;

					// Compute sample cloud density
					float heightFraction, dimensionalProfile;
					float stepDensity = CloudVolumeDensity(rayPos, heightFraction, dimensionalProfile, rayT < 16e3);

					// Skip if no density
					if (stepDensity > cloudEpsilon) {
						// Compute the optical depth of sunlight through clouds
						float opticalDepthSun = CloudVolumeOpticalDepth(rayPos, lightDir, noise.y, CLOUD_LOW_SUNLIGHT_SAMPLES);

						// Approximate sunlight multi-scattering
						float coarseDensity = sqr(dimensionalProfile) * 0.5 + stepDensity;
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
						#endif

						// Estimate the light optical depth of the ground from the cloud volume
						float scatteringGround = oms(dimensionalProfile * saturate(heightFraction * 4.0)) * 0.2 * uniformPhase;

						// Compute In-Scatter Probability
						// See slide 92 of [Schneider, 2017]
						#if 0
							float depthProbability = 0.05 + pow(saturate(stepDensity * 8.0), remap(heightFraction, 0.3, 0.85, 0.5, 2.0));
							float verticalProbability = pow(remap(heightFraction, 0.07, 0.14, 0.1, 1.0), 0.75);
							float inScatterProbability = depthProbability * verticalProbability;
							scatteringSun *= inScatterProbability;
						#endif

						vec2 scattering = vec2(scatteringSun + scatteringGround * worldLightVector.y, scatteringSky);

						float stepOpticalDepth = stepDensity * stepSize;
						float stepTransmittance = exp2(-rLOG2 * cumulusExtinction * stepOpticalDepth);

						// Energy-conserving analytical integration from [Hillaire, 2016]
						float stepIntegral = transmittance * oms(stepTransmittance);
						stepScattering += scattering * stepIntegral;
						transmittance *= stepTransmittance;

						// Break if the cloud has reached the minimum transmittance
						if (transmittance < cloudMinTransmittance) {
							transmittance = 0.0;
							break;
						}
					}
				}

				// Update integral data
				if (transmittance < 1.0 - cloudEpsilon) {
					integralScattering = stepScattering * cumulusAlbedo;
					cloudTransmittance = transmittance;
					cloudDepth = rayLengthWeighted / raySumWeight;
				}
			}
		}
	#endif

	//================================================================================================//

	// Mid-level clouds
	#ifdef CLOUD_ALTOSTRATUS
		if ((mu > 0.0 && r < cloudMidRadius) // Below clouds
		 || (planetIntersection && r > cloudMidRadius)) { // Above clouds
			float rayLength = (cloudMidRadius - r) / mu;
			vec3 rayPos = rayDir * rayLength + camera;

			vec3 cloudTemp = RenderCloudMid(rayPos.xz, rayDir, noise.y, phase);

			// Update integral data
			if (cloudTemp.z > EPS) {
				float transmittanceTemp = 1.0 - cloudTemp.z;

				// Blend layers
				integralScattering = r < cloudMidRadius ?
									 integralScattering + cloudTemp.xy * cloudTransmittance : // Below clouds
									 integralScattering * transmittanceTemp + cloudTemp.xy;  // Above clouds

				// Update transmittance
				cloudTransmittance *= transmittanceTemp;

				// Update cloud depth
				cloudDepth = min(rayLength, cloudDepth);
			}
		}
	#endif

	// High-level clouds
	#if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		if ((mu > 0.0 && r < cloudHighRadius) // Below clouds
		 || (planetIntersection && r > cloudHighRadius)) { // Above clouds
			float rayLength = (cloudHighRadius - r) / mu;
			vec3 rayPos = rayDir * rayLength + camera;

			vec3 cloudTemp = RenderCloudHigh(rayPos.xz, rayDir, noise.y, phase);

			// Update integral data
			if (cloudTemp.z > EPS) {
				float transmittanceTemp = 1.0 - cloudTemp.z;

				// Blend layers
				integralScattering = r < cloudHighRadius ?
									 integralScattering + cloudTemp.xy * cloudTransmittance : // Below clouds
									 integralScattering * transmittanceTemp + cloudTemp.xy;  // Above clouds

				// Update transmittance
				cloudTransmittance *= transmittanceTemp;

				// Update cloud depth
				cloudDepth = min(rayLength, cloudDepth);
			}
		}
	#endif

	//================================================================================================//

    vec3 cloudScattering = vec3(0.0);

	// Composite
	if (cloudTransmittance < 1.0) {
		vec3 cloudPos = camera + rayDir * cloudDepth;

		// Compute irradiance
		vec3 sunIrradiance, moonIrradiance;
		vec3 skyIlluminance = GetSunAndSkyIrradiance(cloudPos, vec3(0.0, 1.0, 0.0), worldSunVector, sunIrradiance, moonIrradiance) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;
		vec3 directIlluminance = SUN_SPECTRAL_RADIANCE_TO_LUMINANCE * mix(sunIrradiance, moonIrradiance, moonlightFactor);
		skyIlluminance += lightningShading * 0.05;

		cloudScattering  = integralScattering.x * PI * directIlluminance;
		cloudScattering += integralScattering.y * rPI * skyIlluminance;
		cloudScattering *= 1.0 - wetness * 0.5;

		// Apply aerial perspective
		#ifdef CLOUD_AERIAL_PERSPECTIVE
			vec3 transmitAP;
			vec3 scatterAP = GetSkyRadianceToPoint(cloudPos, worldSunVector, transmitAP) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;

			cloudScattering *= transmitAP;
			cloudScattering += scatterAP * oms(cloudTransmittance);
		#endif
	}

    return vec4(cloudScattering, cloudTransmittance);
}