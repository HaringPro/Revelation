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
		[Hillaire, 2016] Sebastien Hillaire. “Physically based Sky, Atmosphere and Cloud Rendering”. SIGGRAPH 2016.
			https://www.ea.com/frostbite/news/physically-based-sky-atmosphere-and-cloud-rendering

--------------------------------------------------------------------------------
*/

#include "/lib/atmosphere/clouds/Layers.glsl"

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

    return opticalDepth * (cumulusExtinction * 0.1);
}

float CloudVolumeGroundLightOD(in vec3 rayPos) {
	// Estimate the light optical depth of the ground from the cloud volume
    return max0(rayPos.y - (CLOUD_CU_ALTITUDE + 50.0)) * cumulusExtinction * 0.125;
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
				float density = CloudMidDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun = smin(opticalDepthSun * 0.5, 24.0, 8.0) * -rLOG2;
		}

		// Compute sunlight multi-scattering
		float scatteringSun = 0.0; {
			float falloff = cloudMsFalloff;

			for (uint ms = 0u; ms < cloudMsCount; ++ms, falloff *= 0.5) {
				scatteringSun += exp2(opticalDepthSun) * phases[ms];
				opticalDepthSun *= falloff;
			}
		}

		float opticalDepthSky = density * (-2e2 * rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		float powder = 2.0 * fastExp(-density * 22.0) * oms(fastExp(-density * 44.0));

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIrradiance, moonIrradiance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_MID_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIrradiance, moonIrradiance);
			vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * rPI * directIlluminance;
		scattering += scatteringSky * uniformPhase * skyIlluminance;
		scattering *= oms(0.6 * wetness) * absorption * powder * rcp(cirrusExtinction);

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
			const float stepSize = 64.0 / float(CLOUD_HIGH_SUNLIGHT_SAMPLES);
			vec3 rayStep = vec3(cloudLightVector.xz, 1.0) * stepSize;

			// Compute the optical depth of sunlight through clouds
			for (uint i = 0u; i < CLOUD_HIGH_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xy) {
				float density = CloudHighDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepthSun += density * rayStep.z;
			}

			opticalDepthSun = smin(opticalDepthSun, 24.0, 8.0) * -rLOG2;
		}

		// Compute sunlight multi-scattering
		float scatteringSun = 0.0; {
			float falloff = cloudMsFalloff;

			for (uint ms = 0u; ms < cloudMsCount; ++ms, falloff *= 0.5) {
				scatteringSun += exp2(opticalDepthSun) * phases[ms];
				opticalDepthSun *= falloff;
			}
		}

		float opticalDepthSky = density * (-2e2 * rLOG2);

		// Compute skylight multi-scattering
		// See slide 85 of [Schneider, 2017]
		// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
		float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

		// Compute powder effect
		// Formula from [Schneider, 2015]
		float powder = 2.0 * fastExp(-density * 24.0) * oms(fastExp(-density * 48.0));

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIrradiance, moonIrradiance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_HIGH_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIrradiance, moonIrradiance);
			vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * rPI * directIlluminance;
		scattering += scatteringSky * uniformPhase * skyIlluminance;
		scattering *= oms(0.6 * wetness) * absorption * powder * rcp(cirrusExtinction);

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
		phases[0] = MiePhaseClouds(LdotV, vec3(0.7, -0.4, 0.9), vec3(0.65, 0.25, 0.1));

		for (uint ms = 1u; ms < cloudMsCount; ++ms, falloff *= 0.5) {
			phases[ms] = mix(uniformPhase, phases[0], falloff) * falloff;
		}
	}

	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	//================================================================================================//

	// Low-cloud family
	#ifdef CLOUD_CUMULUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_CU_ALTITUDE) // Below clouds
		 || (clamp(eyeAltitude, CLOUD_CU_ALTITUDE, cumulusMaxAltitude) == eyeAltitude) // In clouds
		 || (rayDir.y < 0.0 && eyeAltitude > cumulusMaxAltitude)) { // Above clouds

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, planetRadius + CLOUD_CU_ALTITUDE, planetRadius + cumulusMaxAltitude);

			if (intersection.y > 0.0) { // Intersect the volume
				// Special treatment for the eye inside the volume
				float withinVolumeSmooth = oms(saturate((eyeAltitude - cumulusMaxAltitude + 5e2) * 2e-3)) * oms(saturate((CLOUD_CU_ALTITUDE - eyeAltitude + 50.0) * 3e-2));
				float stepLength = max0(mix(intersection.y, min(intersection.y, 2e4), withinVolumeSmooth) - intersection.x);

				#if defined PASS_SKY_VIEW
					uint raySteps = uint(CLOUD_CU_SAMPLES * 0.6);
					raySteps = uint(float(raySteps) * oms(abs(rayDir.y) * 0.4)); // Reduce ray steps for vertical rays
				#else
					uint raySteps = CLOUD_CU_SAMPLES;
					// raySteps = uint(raySteps * min1(0.5 + max0(stepLength - 1e2) * 5e-5)); // Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * (withinVolumeSmooth + oms(abs(rayDir.y) * 0.4))); // Reduce ray steps for vertical rays
				#endif

				// const float nearStepSize = 3.0;
				// const float farStepSizeOffset = 60.0;
				// const float stepAdjustmentDistance = 16384.0;

				// float stepSize = nearStepSize + (farStepSizeOffset / stepAdjustmentDistance) * max0(endLength - startLength);

				float stepSize = stepLength * rcp(float(raySteps));

				vec3 rayStep = stepSize * rayDir;
				ToPlanetCurvePos(rayStep);
				vec3 rayPos = (intersection.x + stepSize * dither) * rayDir + cameraPosition;
				ToPlanetCurvePos(rayPos);

				vec3 rayHitPos = vec3(0.0);
				float rayHitPosWeight = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				for (uint i = 0u; i < raySteps; ++i, rayPos += rayStep) {
					if (rayPos.y < CLOUD_CU_ALTITUDE || rayPos.y > cumulusMaxAltitude) continue;

					// Compute sample cloud density
					#if defined PASS_SKY_VIEW
						float stepDensity = CloudVolumeDensity(rayPos, false);
					#else
						float stepDensity = CloudVolumeDensity(rayPos, true);
					#endif

					if (stepDensity < 1e-5) continue;

					rayHitPos += rayPos * transmittance;
					rayHitPosWeight += transmittance;

					#if defined PASS_SKY_VIEW
						vec2 lightNoise = vec2(0.5);
					#else
						// Compute light noise
						vec2 lightNoise = hash2(fract(rayPos));
					#endif

					// Compute the optical depth of sunlight through clouds
					float opticalDepthSun = CloudVolumeSunlightOD(rayPos, lightNoise.x) * -rLOG2;

					// Compute sunlight multi-scattering
					float scatteringSun = 0.0; {
						float falloff = cloudMsFalloff;

						for (uint ms = 0u; ms < cloudMsCount; ++ms, falloff *= 0.5) {
							scatteringSun += exp2(opticalDepthSun) * phases[ms];
							opticalDepthSun *= falloff;
						}
					}

					// Compute the optical depth of skylight through clouds
					float opticalDepthSky = CloudVolumeSkylightOD(rayPos, lightNoise.y) * -rLOG2;
					// See slide 85 of [Schneider, 2017]
					// Original formula: Energy = max( exp( - density_along_light_ray ), (exp(-density_along_light_ray * 0.25) * 0.7) )
					float scatteringSky = exp2(max(opticalDepthSky, opticalDepthSky * 0.25 - 0.5));

					// Compute the optical depth of ground light through clouds
					float opticalDepthGround = CloudVolumeGroundLightOD(rayPos);
					float scatteringGround = exp2(-(opticalDepthGround * rLOG2 + 0.5));

					vec2 scattering = vec2(scatteringSun + scatteringGround * (uniformPhase * cloudLightVector.y), 
										   scatteringSky + scatteringGround);

					float stepOpticalDepth = stepDensity * cumulusExtinction * stepSize;
					float stepTransmittance = fastExp(-stepOpticalDepth);

					// Compute In-Scatter Probability
					// See slide 92 of [Schneider, 2017]
					float heightFraction = saturate((rayPos.y - CLOUD_CU_ALTITUDE) * rcp(CLOUD_CU_THICKNESS));

					float depthProbability = 0.05 + pow(stepDensity * 5.0, remap(heightFraction, 0.25, 0.75, 0.5, 1.5));
					float verticalProbability = pow(remap(heightFraction, 0.07, 0.14, 0.1, 1.0), 0.8);
					float inScatterProbability = depthProbability * verticalProbability;

					// Compute the integral of the scattering over the step
					float stepIntegral = transmittance * oms(stepTransmittance);
					stepScattering += inScatterProbability * scattering * stepIntegral;
					transmittance *= stepTransmittance;	

					if (transmittance < minCloudTransmittance) break;
				}

				float absorption = 1.0 - transmittance;
				if (absorption > minCloudAbsorption) {
					stepScattering *= oms(0.6 * wetness) * rcp(cumulusExtinction);
					rayHitPos /= rayHitPosWeight;
					FromPlanetCurvePos(rayHitPos);
					rayHitPos -= cameraPosition;

					#ifdef CLOUD_LOCAL_LIGHTING
						// Compute local lighting
						vec3 sunIrradiance, moonIrradiance;
						vec3 camera = vec3(0.0, planetRadius + eyeAltitude, 0.0);
						vec3 skyIlluminance = GetSunAndSkyIrradiance(camera + rayHitPos, worldSunVector, sunIrradiance, moonIrradiance);
						vec3 directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);
		
						skyIlluminance += lightningShading * 4e-3;
						#ifdef AURORA
							skyIlluminance += auroraShading;
						#endif
					#endif

					vec3 scattering = stepScattering.x * rPI * directIlluminance;
					scattering += stepScattering.y * uniformPhase * skyIlluminance;

					// Compute aerial perspective
					#ifdef CLOUD_AERIAL_PERSPECTIVE
						vec3 airTransmittance;
						vec3 aerialPerspective = GetSkyRadianceToPoint(rayHitPos, worldSunVector, airTransmittance) * skyIntensity;

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

	// Mid-cloud family
	#if defined CLOUD_ALTOSTRATUS
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

	// High-cloud family
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