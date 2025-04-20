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
			https://www.ea.com/frostbite/news/physically-based-sky-atmosphere-and-cloud-rendering
		[Bauer, 2019] Fabian Bauer. "Creating the Atmospheric World of Red Dead Redemption 2: A Complete and Integrated Solution". SIGGRAPH 2019.
			https://www.advances.realtimerendering.com/s2019/slides_public_release.pptx

--------------------------------------------------------------------------------
*/

#include "/lib/atmosphere/clouds/Shape.glsl"

//================================================================================================//

float CloudVolumeSunlightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = CLOUD_CU_THICKNESS * (0.1 / float(CLOUD_CU_SUNLIGHT_SAMPLES));
	vec4 rayStep = vec4(cloudLightVector, 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CU_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 1.5;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, opticalDepth < 0.25 * rayStep.w);
		// if (density < 1e-5) continue;

        opticalDepth += density * rayStep.w;
        // opticalDepth += density;
    }

    return opticalDepth * cumulusExtinction;
}

float CloudVolumeSkylightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = CLOUD_CU_THICKNESS * (0.1 / float(CLOUD_CU_SKYLIGHT_SAMPLES));
	vec4 rayStep = vec4(vec3(0.0, 1.0, 0.0), 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CU_SKYLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 1.5;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, false);
		// if (density < 1e-5) continue;

        opticalDepth += density * rayStep.w;
        // opticalDepth += density;
    }

    return opticalDepth * (cumulusExtinction * 0.25);
}

float CloudVolumeGroundLightOD(in float density, in float height) {
	// Estimate the light optical depth of the ground from the cloud volume
    return density * height * CLOUD_CU_THICKNESS * cumulusExtinction;
}

//================================================================================================//

vec4 RenderCloudMid(in float stepT, in vec2 rayPos, in vec2 rayDir, in float lightNoise, in float phases[cloudMsCount]) {
	float density = CloudMidDensity(rayPos);
	if (density > 1e-6) {
		float opticalDepth = density * stepT;
		float absorption = oms(exp2(-rLOG2 * opticalDepth));

		float opticalDepthSun = 0.0; {
			const float stepSize = 64.0 / float(CLOUD_MID_SUNLIGHT_SAMPLES);
			vec3 rayStep = vec3(cloudLightVector.xz, 1.0) * stepSize;

			// Compute the optical depth of sunlight through clouds
			for (uint i = 0u; i < CLOUD_MID_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xy) {
				rayStep *= 2.0;

				float density = CloudMidDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun *= cirrusExtinction * -rLOG2;
		}

		// Approximate sunlight multi-scattering
		float scatteringSun = exp2(opticalDepthSun) * phases[0];

		float falloff = cloudMsFalloff;
		for (uint ms = 1u; ms < cloudMsCount; ++ms) {
			scatteringSun += exp2(opticalDepthSun * falloff) * phases[ms];
			falloff *= falloff * approxSqrt(falloff);
		}

		float opticalDepthSky = density * (2e2 * cirrusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		float powder = PI * oms(exp2(-(density * 32.0 + 0.1)));

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIrradiance, moonIrradiance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_MID_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIrradiance, moonIrradiance) * skyIntensity;
			vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * directIlluminance;
		scattering += scatteringSky * uniformPhase * skyIlluminance;
		scattering *= oms(0.6 * wetness) * absorption * powder;

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderCloudHigh(in float stepT, in vec2 rayPos, in vec2 rayDir, in float lightNoise, in float phases[cloudMsCount]) {
	float density = CloudHighDensity(rayPos);
	if (density > 1e-6) {
		float opticalDepth = density * stepT;
		float absorption = oms(exp2(-rLOG2 * opticalDepth));

		float opticalDepthSun = 0.0; {
			const float stepSize = 32.0 / float(CLOUD_HIGH_SUNLIGHT_SAMPLES);
			vec3 rayStep = vec3(cloudLightVector.xz, 1.0) * stepSize;

			// Compute the optical depth of sunlight through clouds
			for (uint i = 0u; i < CLOUD_HIGH_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xy) {
				rayStep *= 2.0;

				float density = CloudHighDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun *= cirrusExtinction * -rLOG2;
		}

		// Approximate sunlight multi-scattering
		float scatteringSun = exp2(opticalDepthSun) * phases[0];

		float falloff = cloudMsFalloff;
		for (uint ms = 1u; ms < cloudMsCount; ++ms) {
			scatteringSun += exp2(opticalDepthSun * falloff) * phases[ms];
			falloff *= falloff * approxSqrt(falloff);
		}

		float opticalDepthSky = density * (1e2 * cirrusExtinction * -rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		float powder = PI * oms(exp2(-(density * 32.0 + 0.1)));

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIrradiance, moonIrradiance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_HIGH_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIrradiance, moonIrradiance) * skyIntensity;
			vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * directIlluminance;
		scattering += scatteringSky * uniformPhase * skyIlluminance;
		scattering *= oms(0.6 * wetness) * absorption * powder;

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderClouds(in vec3 rayDir/* , in vec3 skyRadiance */, in float dither) {
    vec4 cloudData = vec4(0.0, 0.0, 0.0, 1.0);
	float LdotV = dot(cloudLightVector, rayDir);

	// Compute phases for clouds' sunlight multi-scattering
	float phases[cloudMsCount]; {
		float falloff = cloudMsFalloff;
		phases[0] = MiePhaseClouds(LdotV, vec3(0.7, -0.4, 0.9), vec3(0.6, 0.3, 0.1));

		for (uint ms = 1u; ms < cloudMsCount; ++ms) {
			phases[ms] = mix(uniformPhase, phases[0], falloff) * falloff;
			falloff *= cloudMsFalloff;
		}
	}

	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	//================================================================================================//

	// Low-level clouds
	#ifdef CLOUD_CUMULUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_CU_ALTITUDE) // Below clouds
		 || (clamp(eyeAltitude, CLOUD_CU_ALTITUDE, cumulusTopAltitude) == eyeAltitude) // In clouds
		 || (rayDir.y < 0.0 && eyeAltitude > cumulusTopAltitude)) { // Above clouds

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, cumulusBottomRadius, cumulusTopRadius);

			if (intersection.y > 0.0) { // Intersect the volume
				// Special treatment for the eye inside the volume
				float withinVolumeSmooth = oms(saturate((eyeAltitude - cumulusTopAltitude + 5e2) * 2e-3)) * oms(saturate((CLOUD_CU_ALTITUDE - eyeAltitude + 50.0) * 3e-2));
				float rayLength = max0(mix(intersection.y, min(intersection.y, 2e4), withinVolumeSmooth) - intersection.x);

				#if defined PASS_SKY_VIEW
					uint raySteps = uint(CLOUD_CU_SAMPLES * 0.6);
					raySteps = uint(float(raySteps) * oms(abs(rayDir.y) * 0.5)); // Reduce ray steps for vertical rays
				#else
					uint raySteps = CLOUD_CU_SAMPLES;
					// raySteps = uint(raySteps * min1(0.5 + max0(rayLength - 1e2) * 5e-5)); // Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * (withinVolumeSmooth + oms(abs(rayDir.y) * 0.5))); // Reduce ray steps for vertical rays
				#endif

				// From [Schneider, 2022]
				// const float nearStepSize = 3.0;
				// const float farStepSizeOffset = 60.0;
				// const float stepAdjustmentDistance = 16384.0;

				// float stepSize = nearStepSize + (farStepSizeOffset / stepAdjustmentDistance) * rayLength;

				float stepSize = rayLength * rcp(float(raySteps));

				vec3 rayStep = stepSize * rayDir;
				ToPlanetCurvePos(rayStep);

				vec3 rayOrigin = (intersection.x + stepSize * dither) * rayDir;
				vec3 rayPos = rayOrigin + cameraPosition;
				ToPlanetCurvePos(rayPos);

				float rayLengthWeighted = 0.0;
				float raySumWeight = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				// float cloudTest = 0.0;
				// uint zeroDensityCounter = 0u;

				for (uint i = 0u; i < raySteps; ++i) {
					// Advance to the next sample position
					rayPos += rayStep;

					// if (cloudTest < 1e-5) {
					// 	cloudTest = CloudVolumeDensity(rayPos, false);
					// 	if (cloudTest < 1e-5) {
					// 		rayPos += rayStep;
					// 	}
					// 	continue;
					// }

					// Compute sample cloud density
					float heightFraction;
					float stepDensity = CloudVolumeDensity(rayPos, heightFraction);

					// if (stepDensity < 1e-5) {
					// 	++zeroDensityCounter;
					// }

					// if (zeroDensityCounter > 5u) {
					// 	cloudTest = 0.0;
					// 	zeroDensityCounter = 0u;
					// 	continue;
					// }

					rayLengthWeighted += stepSize * float(i) * transmittance;
					raySumWeight += transmittance;

					#if defined PASS_SKY_VIEW
						vec2 lightNoise = vec2(0.5);
					#else
						// Compute light noise
						vec2 lightNoise = hash2(fract(rayPos));
					#endif

					// Compute the optical depth of sunlight through clouds
					float opticalDepthSun = CloudVolumeSunlightOD(rayPos, lightNoise.x) * -rLOG2;

					// Approximate sunlight multi-scattering
					float scatteringSun = exp2(opticalDepthSun) * phases[0];

					float falloff = cloudMsFalloff;
					for (uint ms = 1u; ms < cloudMsCount; ++ms) {
						scatteringSun += exp2(opticalDepthSun * falloff) * phases[ms];
						falloff *= falloff * approxSqrt(falloff);
					}

					// Compute the optical depth of skylight through clouds
					float opticalDepthSky = CloudVolumeSkylightOD(rayPos, lightNoise.y) * -rLOG2;
					// See slide 85 of [Schneider, 2017]
					// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
					float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5) - 1.0);

					// Compute the optical depth of ground light through clouds
					float opticalDepthGround = CloudVolumeGroundLightOD(stepDensity, heightFraction);
					float scatteringGround = fastExp(-opticalDepthGround);

					vec2 scattering = vec2(scatteringSun + scatteringGround * (uniformPhase * cloudLightVector.y), 
										   scatteringSky + scatteringGround);

					float stepOpticalDepth = stepDensity * (cumulusExtinction * -rLOG2) * stepSize;
					float stepTransmittance = exp2(stepOpticalDepth);

					// Compute In-Scatter Probability
					// See slide 92 of [Schneider, 2017]
					float depthProbability = 0.05 + pow(stepDensity * 6.0, remap(heightFraction, 0.3, 0.85, 0.5, 1.5));
					float verticalProbability = pow(remap(heightFraction, 0.07, 0.14, 0.1, 1.0), 0.8);
					float inScatterProbability = depthProbability * verticalProbability;

					// Compute the integral of the scattering over the step
					float stepIntegral = transmittance * oms(stepTransmittance);
					stepScattering += inScatterProbability * scattering * stepIntegral;
					transmittance *= stepTransmittance;	

					// Break if the cloud has reached the minimum transmittance
					if (transmittance < minCloudTransmittance) break;
				}

				float absorption = 1.0 - transmittance;
				if (absorption > minCloudAbsorption) {
					vec3 rayPosWeighted = rayOrigin + (rayLengthWeighted / raySumWeight) * rayDir;

					#ifdef CLOUD_LOCAL_LIGHTING
						// Compute local lighting
						vec3 sunIrradiance, moonIrradiance;
						vec3 camera = vec3(0.0, planetRadius + eyeAltitude, 0.0);
						vec3 skyIlluminance = GetSunAndSkyIrradiance(camera + rayPosWeighted, worldSunVector, sunIrradiance, moonIrradiance) * skyIntensity;
						vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);
		
						skyIlluminance += lightningShading * 4e-3;
						#ifdef AURORA
							skyIlluminance += auroraShading;
						#endif
					#endif

					stepScattering *= oms(0.6 * wetness) * PI;
					vec3 scattering = stepScattering.x * directIlluminance;
					scattering += stepScattering.y * uniformPhase * skyIlluminance;

					// Compute aerial perspective
					#ifdef CLOUD_AERIAL_PERSPECTIVE
						vec3 airTransmittance;
						vec3 aerialPerspective = GetSkyRadianceToPoint(rayPosWeighted, worldSunVector, airTransmittance) * skyIntensity;

						scattering *= airTransmittance;
						scattering += aerialPerspective * absorption;
					#endif

					// Remap cloud transmittance
					transmittance = remap(minCloudTransmittance, 1.0, transmittance);

					cloudData = vec4(scattering, transmittance);
				}
			}
		}
	#endif

	//================================================================================================//

	bool planetIntersection = RayIntersectsGround(r, mu);

	// Mid-level clouds
	#ifdef CLOUD_ALTOSTRATUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_MID_ALTITUDE) // Below clouds
		 || (planetIntersection && eyeAltitude > CLOUD_MID_ALTITUDE)) { // Above clouds
			float cloudDistance = (planetRadius + CLOUD_MID_ALTITUDE - r) / mu;
			vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

			vec4 cloudTemp = RenderCloudMid(cloudDistance * stratusExtinction, cloudPos.xz, rayDir.xz, dither, phases);

			// Compute aerial perspective
			#ifdef CLOUD_AERIAL_PERSPECTIVE
				if (cloudTemp.a > minCloudAbsorption) {
					vec3 airTransmittance;
					vec3 aerialPerspective = GetSkyRadianceToPoint(cloudPos - cameraPosition, worldSunVector, airTransmittance) * skyIntensity;
					cloudTemp.rgb *= airTransmittance;
					cloudTemp.rgb += aerialPerspective * cloudTemp.a;
				}
			#endif
			// Absorption to transmittance
			cloudTemp.a = 1.0 - cloudTemp.a;

			// Blend layers
			cloudData.rgb = eyeAltitude < CLOUD_MID_ALTITUDE ?
							cloudData.rgb + cloudTemp.rgb * cloudData.a : // Below clouds
							cloudData.rgb * cloudTemp.a + cloudTemp.rgb;  // Above clouds

			cloudData.a *= cloudTemp.a;
		}
	#endif

	// High-level clouds
	#if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_HIGH_ALTITUDE) // Below clouds
		 || (planetIntersection && eyeAltitude > CLOUD_HIGH_ALTITUDE)) { // Above clouds
			float cloudDistance = (planetRadius + CLOUD_HIGH_ALTITUDE - r) / mu;
			vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

			vec4 cloudTemp = RenderCloudHigh(cloudDistance * cirrusExtinction, cloudPos.xz, rayDir.xz, dither, phases);

			// Compute aerial perspective
			#ifdef CLOUD_AERIAL_PERSPECTIVE
				if (cloudTemp.a > minCloudAbsorption) {
					vec3 airTransmittance;
					vec3 aerialPerspective = GetSkyRadianceToPoint(cloudPos - cameraPosition, worldSunVector, airTransmittance) * skyIntensity;
					cloudTemp.rgb *= airTransmittance;
					cloudTemp.rgb += aerialPerspective * cloudTemp.a;
				}
			#endif
			// Absorption to transmittance
			cloudTemp.a = 1.0 - cloudTemp.a;

			// Blend layers
			cloudData.rgb = eyeAltitude < CLOUD_HIGH_ALTITUDE ?
							cloudData.rgb + cloudTemp.rgb * cloudData.a : // Below clouds
							cloudData.rgb * cloudTemp.a + cloudTemp.rgb;  // Above clouds
			cloudData.a *= cloudTemp.a;
		}
	#endif

	// Remap cloud transmittance
    cloudData.a = remap(minCloudTransmittance, 1.0, cloudData.a);

	#ifdef AURORA
		if (auroraAmount > 1e-2) cloudData.rgb += NightAurora(rayDir) * cloudData.a;
	#endif

    return cloudData;
}

#include "/lib/atmosphere/clouds/Shadows.glsl"

uniform vec3 fmExtinction;
uniform vec3 fmScattering;
uniform vec3 frExtinction;
uniform vec3 frScattering;

vec4 RaymarchCrepuscular(in vec3 rayDir, in float dither) {
	const uint steps = 12u;

	// if (RayIntersectsGround(viewerHeight, rayDir.y) && viewerHeight < cumulusBottomRadius) return vec4(vec3(0.0), 1.0);

	// From planet to cumulus top
	vec2 intersection = RaySphericalShellIntersection(viewerHeight, rayDir.y, planetRadius, cumulusTopRadius);

	// Not intersecting the volume
	if (intersection.y < 0.0) return vec4(vec3(0.0), 1.0);

	float rayLength = clamp(intersection.y - intersection.x, 0.0, 8192.0);
	float stepLength = rayLength * rcp(float(steps));

	// In shadow view space
	float projectionScale = rcp(min(CLOUD_SHADOW_DISTANCE, CSD_INF));

	vec3 rayStep = mat3(shadowModelView) * rayDir;
	vec3 rayPos = shadowModelView[3].xyz + rayStep * intersection.x;
	rayPos *= projectionScale;

	rayStep *= stepLength * projectionScale;
	rayPos += rayStep * dither;

	// Mie + Rayleigh
	float LdotV = dot(worldLightVector, rayDir);
	vec2 phase = vec2(CornetteShanksPhase(LdotV, 0.65), RayleighPhase(LdotV));

	vec3 extinctionCoeff = (fmExtinction * (2.0 - timeNoon + wetness * 8.0) + frExtinction) * 3e-7;
	mat2x3 scatteringCoeff = mat2x3(fmScattering * (2.0 - timeNoon + wetness * 8.0), frScattering) * 3e-7;

	vec3 stepTransmittance = exp2(-rLOG2 * extinctionCoeff * stepLength);

	vec3 scattering = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
		vec2 cloudShadowCoord = DistortCloudShadowPos(rayPos);
		float visibility = texture(colortex10, cloudShadowCoord).x;
		scattering += sqr(visibility) * transmittance;

		transmittance *= stepTransmittance;
	}

	// Direct only
	scattering *= scatteringCoeff * phase * oms(stepTransmittance) / extinctionCoeff * directIlluminance;

	return vec4(scattering, mean(transmittance));
}
