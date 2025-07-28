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

float CloudVolumeOpticalDepth(in vec3 rayPos, in vec3 rayDir, in float lightNoise, in uint steps) {
    const float stepSize = 256.0 / float(steps);
	vec4 rayStep = vec4(rayDir, 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < steps; ++i, rayPos += rayStep.xyz) {
        rayStep *= 1.5;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, opticalDepth < 0.25 * rayStep.w);
        opticalDepth += density * rayStep.w;
    }

    return opticalDepth * cumulusExtinction;
}

// Approximate method from [Wrenninge et al., 2013]
float CloudMultiScatteringApproximation(in float opticalDepth, in float phases[cloudMsCount]) {
	float scatteringFalloff = cloudMsFalloffA;
	float extinctionFalloff = cloudMsFalloffB;

	// opticalDepth has already been multiplied by -rLOG2 so we can use exp2() directly
	float scattering = exp2(opticalDepth) * phases[0];

	for (uint ms = 1u; ms < cloudMsCount; ++ms) {
		scattering += exp2(opticalDepth * extinctionFalloff) * phases[ms] * scatteringFalloff;

		scatteringFalloff *= scatteringFalloff;
		extinctionFalloff *= extinctionFalloff;
	}

	return scattering;
}

//================================================================================================//

vec3 RenderCloudMid(in vec2 rayPos, in vec3 rayDir, in float lightNoise, in float phases[cloudMsCount]) {
	float density = CloudMidDensity(rayPos);
	if (density > cloudEpsilon) {
		float opticalDepth = density * CLOUD_MID_THICKNESS / abs(rayDir.y);
		float integral = oms(exp2(-rLOG2 * stratusExtinction * opticalDepth));

		float opticalDepthSun = 0.0; {
			const float stepSize = 128.0 / float(CLOUD_MID_SUNLIGHT_SAMPLES);
			vec3 rayStep = vec3(worldLightVector.xz, 1.0) * stepSize;

			// Compute the optical depth of sunlight through clouds
			for (uint i = 0u; i < CLOUD_MID_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xy) {
				rayStep *= 2.0;

				float density = CloudMidDensity(rayPos + rayStep.xy * lightNoise);

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun *= stratusExtinction * -rLOG2;
		}

		// Approximate sunlight multi-scattering
		float scatteringSun = CloudMultiScatteringApproximation(opticalDepthSun, phases);

		float opticalDepthSky = density * (CLOUD_MID_THICKNESS * stratusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		// float powder = 2.0 * oms(exp2(-(density * 32.0 + 0.1)));

		// TODO: Better implementation
		float inScatterProbability = oms(exp2(-(density * 16.0 + 0.25)));

		scatteringSun *= integral * inScatterProbability * stratusAlbedo;
		scatteringSky *= integral * stratusAlbedo;
		return vec3(scatteringSun, scatteringSky, integral);
	} else {
		return vec3(0.0);
	}
}

//================================================================================================//

vec3 RenderCloudHigh(in vec2 rayPos, in vec3 rayDir, in float lightNoise, in float phases[cloudMsCount]) {
	float density = CloudHighDensity(rayPos);
	if (density > cloudEpsilon) {
		float opticalDepth = density * CLOUD_HIGH_THICKNESS / abs(rayDir.y);
		float integral = oms(exp2(-rLOG2 * cirrusExtinction * opticalDepth));

		float opticalDepthSun = 0.0; {
			const float stepSize = 128.0 / float(CLOUD_HIGH_SUNLIGHT_SAMPLES);
			vec3 rayStep = vec3(worldLightVector.xz, 1.0) * stepSize;

			// Compute the optical depth of sunlight through clouds
			for (uint i = 0u; i < CLOUD_HIGH_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xy) {
				rayStep *= 2.0;

				float density = CloudHighDensity(rayPos + rayStep.xy * lightNoise);

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun *= cirrusExtinction * -rLOG2;
		}

		// Approximate sunlight multi-scattering
		float scatteringSun = CloudMultiScatteringApproximation(opticalDepthSun, phases);

		float opticalDepthSky = density * (CLOUD_HIGH_THICKNESS * cirrusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		// float powder = 2.0 * oms(exp2(-(density * 32.0 + 0.1)));

		// TODO: Better implementation
		float inScatterProbability = oms(exp2(-(density * 16.0 + 0.25)));

		scatteringSun *= integral * inScatterProbability * cirrusAlbedo;
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

vec4 RenderClouds(in vec3 rayDir/* , in vec3 skyRadiance */, in float dither, out float cloudDepth) {
	float LdotV = dot(worldLightVector, rayDir);

	// Compute phases for clouds' sunlight multi-scattering
	float phase = TripleLobePhase(LdotV, cloudForwardG, cloudBackwardG, cloudLobeMixer, cloudSilverG, cloudSilverI);
	// float phase = HgDrainePhase(LdotV, 35.0);
	float phases[cloudMsCount] = SetupParticipatingMediaPhases(phase, cloudMsFalloffC);

	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	bool planetIntersection = RayIntersectsGround(r, mu);

	vec3 cloudViewerPos = vec3(cameraPosition.xz, r).xzy;

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
				float withinVolumeSmooth = remap(CLOUD_CU_THICKNESS + 32.0, CLOUD_CU_THICKNESS - 64.0, abs(r * 2.0 - (cumulusBottomRadius + cumulusTopRadius)));

				float rayLength = clamp(intersection.y - intersection.x, 0.0, 1e5 - withinVolumeSmooth * 6e4);

				#if defined PASS_SKY_VIEW
					uint raySteps = CLOUD_CU_SAMPLES >> 1u;
					// Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * oms(abs(mu) * 0.5));
				#else
					uint raySteps = CLOUD_CU_SAMPLES;
					// Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * mix(oms(abs(mu) * 0.5), 4.0, withinVolumeSmooth));
				#endif

				// From [Schneider, 2022]
				// const float nearStepSize = 3.0;
				// const float farStepSizeOffset = 60.0;
				// const float stepAdjustmentDistance = 16384.0;

				// float stepSize = nearStepSize + (farStepSizeOffset / stepAdjustmentDistance) * rayLength;

				float stepSize = rayLength * rcp(float(raySteps));

				float startLength = intersection.x + stepSize * dither;
				vec3 rayPos = startLength * rayDir + cloudViewerPos;
				vec3 rayStep = stepSize * rayDir;

				float rayLengthWeighted = 0.0;
				float raySumWeight = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				// float cloudTest = 0.0;
				// uint zeroDensityCounter = 0u;

				// Raymarch through the cloud volume
				for (uint i = 1u; i <= raySteps; ++i) {
					// Advance to the next sample position
					rayPos += rayStep;

					// Method from [Hillaire, 2016]
					// Accumulate the weighted ray length
					rayLengthWeighted += stepSize * float(i) * transmittance;
					raySumWeight += transmittance;

					// if (cloudTest < cloudEpsilon) {
					// 	cloudTest = CloudVolumeDensity(rayPos, false);
					// 	if (cloudTest < cloudEpsilon) {
					// 		rayPos += rayStep;
					// 	}
					// 	continue;
					// }

					// Compute sample cloud density
					float heightFraction, dimensionalProfile;
					float stepDensity = CloudVolumeDensity(rayPos, heightFraction, dimensionalProfile);

					if (stepDensity < cloudEpsilon) continue;

					// if (stepDensity < cloudEpsilon) {
					// 	++zeroDensityCounter;
					// }

					// if (zeroDensityCounter > 5u) {
					// 	cloudTest = 0.0;
					// 	zeroDensityCounter = 0u;
					// 	continue;
					// }

					#if defined PASS_SKY_VIEW
						vec2 lightNoise = vec2(0.5);
					#else
						// Compute light noise
						vec2 lightNoise = hash2(fract(rayPos));
					#endif

					// Compute the optical depth of sunlight through clouds
					float opticalDepthSun = CloudVolumeOpticalDepth(rayPos, worldLightVector, lightNoise.x, CLOUD_CU_SUNLIGHT_SAMPLES) * -rLOG2;

					// Nubis Multiscatter Approximation
					// float msVolume = remap(0.15, 0.85, dimensionalProfile);
					// float scatteredEnergy = msVolume;

					// Approximate sunlight multi-scattering
					float scatteringSun = CloudMultiScatteringApproximation(opticalDepthSun, phases);

					#if CLOUD_CU_SKYLIGHT_SAMPLES > 0
						// Compute the optical depth of skylight through clouds
						float opticalDepthSky = CloudVolumeOpticalDepth(rayPos, vec3(0.0, 1.0, 0.0), lightNoise.y, CLOUD_CU_SKYLIGHT_SAMPLES) * -rLOG2;

						// See slide 85 of [Schneider, 2017]
						// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
						float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));
					#else
						// Nubis Ambient Scattering Approximation
						float scatteringSky = approxSqrt(1.0 - dimensionalProfile) * saturate(heightFraction * 2.0);
					#endif

					// Estimate the light optical depth of the ground from the cloud volume
					float opticalDepthGround = stepDensity * heightFraction * (CLOUD_CU_THICKNESS * cumulusExtinction * -rLOG2);
					float scatteringGround = exp2(max(opticalDepthGround, opticalDepthGround * 0.25 - 0.5)) * rPI;

					// Compute In-Scatter Probability
					// See slide 92 of [Schneider, 2017]
					// float depthProbability = 0.05 + pow(saturate(stepDensity * 8.0), remap(heightFraction, 0.3, 0.85, 0.5, 2.0));
					// float verticalProbability = pow(remap(heightFraction, 0.07, 0.14, 0.1, 1.0), 0.75);
					// float inScatterProbability = depthProbability * verticalProbability;
					// scatteringSun *= inScatterProbability;
					float inScatterProbability = sqr(stepDensity * 2.0 + dimensionalProfile);
					scatteringSun *= inScatterProbability * 2.0;

					vec2 scattering = vec2(scatteringSun + scatteringGround * uniformPhase * worldLightVector.y, 
										   scatteringSky + scatteringGround);

					float stepOpticalDepth = stepDensity * (cumulusExtinction * -rLOG2) * stepSize;
					float stepTransmittance = exp2(stepOpticalDepth);

					// Energy-conserving analytical integration from [Hillaire, 2016]
					float stepIntegral = transmittance * oms(stepTransmittance);
					stepScattering += scattering * stepIntegral;
					transmittance *= stepTransmittance;	

					// Break if the cloud has reached the minimum transmittance
					if (transmittance < cloudMinTransmittance) break;
				}

				// Remap to [0, 1]
				transmittance = remap(cloudMinTransmittance, 1.0, transmittance);

				// Update integral data
				if (transmittance < 1.0 - cloudEpsilon) {
					integralScattering = stepScattering * cumulusAlbedo;
					cloudTransmittance = transmittance;
					cloudDepth = startLength + rayLengthWeighted / raySumWeight;
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
			vec3 rayPos = rayDir * rayLength + cloudViewerPos;

			vec3 cloudTemp = RenderCloudMid(rayPos.xz, rayDir, dither, phases);

			// Update integral data
			if (cloudTemp.z > cloudEpsilon) {
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
			vec3 rayPos = rayDir * rayLength + cloudViewerPos;

			vec3 cloudTemp = RenderCloudHigh(rayPos.xz, rayDir, dither, phases);

			// Update integral data
			if (cloudTemp.z > cloudEpsilon) {
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
	if (cloudTransmittance < 1.0 - cloudEpsilon) {
		vec3 cloudPos = rayDir * cloudDepth;

		// Compute irradiance
		vec3 sunIrradiance, moonIrradiance;
		vec3 camera = vec3(0.0, viewerHeight, 0.0);
		vec3 skyIlluminance = GetSunAndSkyIrradiance(camera + cloudPos, vec3(0.0, 1.0, 0.0), worldSunVector, sunIrradiance, moonIrradiance) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;
		vec3 directIlluminance = SUN_SPECTRAL_RADIANCE_TO_LUMINANCE * (sunIrradiance + moonIrradiance);

		skyIlluminance += lightningShading * 0.05;
		#ifdef AURORA
			skyIlluminance += auroraShading;
		#endif

		// Direct + Indirect
		cloudScattering  = integralScattering.x * oms(wetness * 0.5) * directIlluminance;
		cloudScattering += integralScattering.y * uniformPhase * skyIlluminance;
		cloudScattering *= PI;

		// Compute aerial perspective
		#ifdef CLOUD_AERIAL_PERSPECTIVE
			vec3 transmitAP;
			vec3 scatterAP = GetSkyRadianceToPoint(cloudPos, worldSunVector, transmitAP) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;

			cloudScattering *= transmitAP;
			cloudScattering += scatterAP * oms(cloudTransmittance);
		#endif
	}

	#ifdef AURORA
		if (auroraAmount > 1e-2) cloudScattering += NightAurora(rayDir) * cloudTransmittance;
	#endif

    return vec4(cloudScattering, cloudTransmittance);
}

//================================================================================================//

#include "/lib/atmosphere/clouds/Shadows.glsl"

vec4 RaymarchCrepuscular(in vec3 rayDir, in float dither) {
	uint steps = uint(float(CREPUSCULAR_RAYS_SAMPLES) * oms(abs(rayDir.y) * 0.5)); // Reduce ray steps for vertical rays

	// if (RayIntersectsGround(viewerHeight, rayDir.y) && viewerHeight < cumulusBottomRadius) return vec4(vec3(0.0), 1.0);

	// From planet to cumulus top
	vec2 intersection = RaySphericalShellIntersection(viewerHeight, rayDir.y, planetRadius, cumulusTopRadius);

	// Not intersecting the volume
	if (intersection.y < 0.0) return vec4(vec3(0.0), 1.0);

	float rayLength = clamp(intersection.y - intersection.x, 0.0, 2e4);
	float stepLength = rayLength * rcp(float(steps));

	// In shadow view space
	const float projectionScale = rcp(CLOUD_SHADOW_DISTANCE) * 0.5;

	vec2 rayStep = (mat3(shadowModelView) * rayDir).xy;
	vec2 rayPos = shadowModelView[3].xy + rayStep * intersection.x;
	rayPos *= projectionScale;

	rayStep *= stepLength * projectionScale;
	rayPos += rayStep * dither + 0.5;

	// Mie + Rayleigh
	float LdotV = dot(worldLightVector, rayDir);
	vec2 phase = vec2(CornetteShanksPhase(LdotV, 0.65), RayleighPhase(LdotV));

	float mieDensity = 2.0 * oms(timeNoon - wetness);
	vec3 extinctionCoeff = (atmosphereModel.mie_extinction * mieDensity + atmosphereModel.rayleigh_scattering) * (2e-3 * CREPUSCULAR_RAYS_INTENSITY);
	mat2x3 scatteringCoeff = mat2x3(atmosphereModel.mie_scattering * mieDensity, atmosphereModel.rayleigh_scattering) * (2e-3 * CREPUSCULAR_RAYS_INTENSITY);

	vec3 stepTransmittance = exp2(-rLOG2 * extinctionCoeff * stepLength);

	vec3 scattering = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	// Raymarch through the volume
	for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
		// vec2 cloudShadowCoord = DistortCloudShadowPos(rayPos);
		float visibility = texture(colortex10, rayPos.xy).x;
		scattering += visibility * transmittance;

		transmittance *= stepTransmittance;
	}

	// Process scattering
	scattering *= scatteringCoeff * phase * oms(stepTransmittance) * loadDirectIllum();
	scattering += (scatteringCoeff[0] + scatteringCoeff[1]) * uniformPhase * oms(transmittance) * loadSkyIllum();

	return vec4(scattering / extinctionCoeff, mean(transmittance));
}