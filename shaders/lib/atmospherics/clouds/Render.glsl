/*
--------------------------------------------------------------------------------

	Referrence: 
		https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn
		http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
		https://odr.chalmers.se/server/api/core/bitstreams/c8634b02-1b52-40c7-a75c-d8c7a9594c2c/content
		https://advances.realtimerendering.com/s2017/Nubis%20-%20Authoring%20Realtime%20Volumetric%20Cloudscapes%20with%20the%20Decima%20Engine%20-%20Final.pptx
		https://advances.realtimerendering.com/s2022/SIGGRAPH2022-Advances-NubisEvolved-NoVideos.pdf

--------------------------------------------------------------------------------
*/

#include "Layers.glsl"

//================================================================================================//

float CloudVolumeSunlightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = CLOUD_CUMULUS_THICKNESS * (0.1 / float(CLOUD_CUMULUS_SUNLIGHT_SAMPLES));
	vec4 rayStep = vec4(cloudLightVector, 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CUMULUS_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 2.0;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, max(2u, 5u - i));
		if (density < 1e-5) continue;

        // opticalDepth += density * rayStep.w;
        opticalDepth += density;
    }

    return opticalDepth * 9.0;
}

float CloudVolumeSkylightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = CLOUD_CUMULUS_THICKNESS * (0.1 / float(CLOUD_CUMULUS_SKYLIGHT_SAMPLES));
	vec4 rayStep = vec4(vec3(0.0, 1.0, 0.0), 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CUMULUS_SKYLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 2.0;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, max(2u, 4u - i));
		if (density < 1e-5) continue;

        // opticalDepth += density * rayStep.w;
        opticalDepth += density;
    }

    return opticalDepth * 2.0;
}

float CloudVolumeGroundLightOD(in vec3 rayPos) {
	// Estimate the light optical depth of the ground from the cloud volume
    return max0(rayPos.y - (CLOUD_CUMULUS_ALTITUDE + 40.0)) * 2.4e-2;
}

float CloudPowderEffect(in float depth, in float height, in float factor){
    return depth * (height + oneMinus(height) * factor);
}

//================================================================================================//

vec4 RenderCloudMid(in float stepT, in vec2 rayPos, in vec2 rayDir, in float LdotV, in float lightNoise, in vec4 phases) {
	float density = CloudMidDensity(rayPos);
	if (density > 1e-6) {
		// Siggraph 2017's new formula
		float opticalDepth = density * stepT;
		float absorption = oneMinus(max(fastExp(-opticalDepth), fastExp(-opticalDepth * 0.25) * 0.7));

		float stepSize = 42.0;
		vec2 rayPos = rayPos;
		vec3 rayStep = vec3(cloudLightVector.xz, 1.0) * stepSize;
		// float lightNoise = hash1(rayPos);

		opticalDepth = 0.0;
		// Compute the optical depth of sunlight through clouds
		for (uint i = 0u; i < 3u; ++i, rayPos += rayStep.xy) {
			float density = CloudMidDensity(rayPos + rayStep.xy * lightNoise);
			if (density < 1e-6) continue;

			rayStep *= 2.0;

			opticalDepth += density * rayStep.z;
		} opticalDepth = smin(opticalDepth * 0.5, 46.0, 8.0);

		// Magic power function, looks not bad
		vec4 hitPhases = pow(phases, vec4(0.7 + 0.2 * saturate(opticalDepth)));

		// Compute sunlight multi-scattering
		float scatteringSun  = fastExp(-opticalDepth * 1.0)  * hitPhases.x;
			  scatteringSun += fastExp(-opticalDepth * 0.4)  * hitPhases.y;
			  scatteringSun += fastExp(-opticalDepth * 0.15) * hitPhases.z;
			  scatteringSun += fastExp(-opticalDepth * 0.05) * hitPhases.w;

		#if 0
			stepSize = 44.0;
			rayStep = vec3(rayDir, 1.0) * stepSize;

			opticalDepth = 0.0;
			// Compute the optical depth of skylight through clouds
			for (uint i = 0u; i < 2u; ++i, rayPos += rayStep.xy) {
				float density = CloudMidDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepth += density * rayStep.z;
			}
		#else
			opticalDepth = density * 2e2;
		#endif

		// Compute skylight multi-scattering
		float scatteringSky = fastExp(-opticalDepth * 0.2);
		scatteringSky += 0.2 * fastExp(-opticalDepth * 0.04);

		// Compute powder effect
		// float powder = 2.0 * fastExp(-density * 36.0) * oneMinus(fastExp(-density * 72.0));
		float powder = rcp(fastExp(-density * (PI * 3.0 / stratusExtinction)) * 0.75 + 0.25) - 1.0;
		powder += oneMinus(powder) * sqr(LdotV * 0.5 + 0.5) * saturate(density * 5.0);

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIlluminance, moonIlluminance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_MID_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIlluminance, moonIlluminance);
			vec3 directIlluminance = sunIlluminance + moonIlluminance;

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * 12.0 * powder * directIlluminance;
		scattering += scatteringSky * 0.1 * (powder * 0.5 + 0.5) * skyIlluminance;
		scattering *= oneMinus(0.6 * wetness) * absorption * rcp(stratusExtinction);

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderCloudHigh(in float stepT, in vec2 rayPos, in vec2 rayDir, in float LdotV, in float lightNoise, in vec4 phases) {
	float density = CloudHighDensity(rayPos);
	if (density > 1e-6) {
		// Siggraph 2017's new formula
		float opticalDepth = density * stepT;
		float absorption = oneMinus(max(fastExp(-opticalDepth), fastExp(-opticalDepth * 0.25) * 0.7));

		float stepSize = 42.0;
		vec2 rayPos = rayPos;
		vec3 rayStep = vec3(cloudLightVector.xz, 1.0) * stepSize;
		// float lightNoise = hash1(rayPos);

		opticalDepth = 0.0;
		// Compute the optical depth of sunlight through clouds
		for (uint i = 0u; i < 3u; ++i, rayPos += rayStep.xy) {
			float density = CloudHighDensity(rayPos + rayStep.xy * lightNoise);
			if (density < 1e-6) continue;

			rayStep *= 2.0;

			opticalDepth += density * rayStep.z;
		} opticalDepth = smin(opticalDepth * 0.5, 24.0, 8.0);

		// Magic power function, looks not bad
		vec4 hitPhases = pow(phases, vec4(0.7 + 0.2 * saturate(opticalDepth)));

		// Compute sunlight multi-scattering
		float scatteringSun  = fastExp(-opticalDepth * 1.0)  * hitPhases.x;
			  scatteringSun += fastExp(-opticalDepth * 0.4)  * hitPhases.y;
			  scatteringSun += fastExp(-opticalDepth * 0.15) * hitPhases.z;
			  scatteringSun += fastExp(-opticalDepth * 0.05) * hitPhases.w;

		#if 0
			stepSize = 44.0;
			rayStep = vec3(rayDir, 1.0) * stepSize;

			opticalDepth = 0.0;
			// Compute the optical depth of skylight through clouds
			for (uint i = 0u; i < 2u; ++i, rayPos += rayStep.xy) {
				float density = CloudHighDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepth += density * rayStep.z;
			}
		#else
			opticalDepth = density * 2e2;
		#endif

		// Compute skylight multi-scattering
		float scatteringSky = fastExp(-opticalDepth * 0.2);
		scatteringSky += 0.2 * fastExp(-opticalDepth * 0.04);

		// Compute powder effect
		float powder = 2.0 * fastExp(-density * 22.0) * oneMinus(fastExp(-density * 44.0));
		// float powder = rcp(fastExp(-density * (PI * 3.0 / cirrusExtinction)) * 0.6 + 0.4) - 1.0;
		powder += oneMinus(powder) * sqr(LdotV * 0.5 + 0.5) * saturate(density * 5.0);

		#ifdef CLOUD_LOCAL_LIGHTING
			// Compute local lighting
			vec3 sunIlluminance, moonIlluminance;
			vec3 hitPos = vec3(rayPos.x, planetRadius + eyeAltitude + CLOUD_HIGH_ALTITUDE, rayPos.y);
			vec3 skyIlluminance = GetSunAndSkyIrradiance(hitPos, worldSunVector, sunIlluminance, moonIlluminance);
			vec3 directIlluminance = sunIlluminance + moonIlluminance;

			skyIlluminance += lightningShading * 4e-3;
			#ifdef AURORA
				skyIlluminance += auroraShading;
			#endif
		#endif

		vec3 scattering = scatteringSun * 12.0 * powder * directIlluminance;
		scattering += scatteringSky * 0.1 * (powder * 0.5 + 0.5) * skyIlluminance;
		scattering *= oneMinus(0.6 * wetness) * absorption * rcp(cirrusExtinction);

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderClouds(in vec3 rayDir/* , in vec3 skyRadiance */, in float dither) {
    vec4 cloudData = vec4(0.0, 0.0, 0.0, 1.0);
	float LdotV = dot(cloudLightVector, rayDir);

	// Compute phases for clouds' sunlight multi-scattering
	vec4 phases = vec4(
		MiePhaseClouds(LdotV, vec3(0.65, -0.4, 0.9), 	   vec3(0.65, 0.25, 0.1)),
		MiePhaseClouds(LdotV, vec3(0.65, -0.4, 0.9) * 0.7, vec3(0.65, 0.25, 0.1) * 0.55),
		MiePhaseClouds(LdotV, vec3(0.65, -0.4, 0.9) * 0.5, vec3(0.65, 0.25, 0.1) * 0.3),
		MiePhaseClouds(LdotV, vec3(0.65, -0.4, 0.9) * 0.3, vec3(0.65, 0.25, 0.1) * 0.17)
	);

	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	//================================================================================================//

	// Compute volumetric clouds
	#ifdef CLOUD_CUMULUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_CUMULUS_ALTITUDE) // Below clouds
		 || (clamp(eyeAltitude, CLOUD_CUMULUS_ALTITUDE, cumulusMaxAltitude) == eyeAltitude) // In clouds
		 || (rayDir.y < 0.0 && eyeAltitude > cumulusMaxAltitude)) { // Above clouds

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, planetRadius + CLOUD_CUMULUS_ALTITUDE, planetRadius + cumulusMaxAltitude);

			if (intersection.y > 0.0) { // Intersect the volume
				// Special treatment for the eye inside the volume
				float withinVolumeSmooth = oneMinus(saturate((eyeAltitude - cumulusMaxAltitude + 5e2) * 2e-3)) * oneMinus(saturate((CLOUD_CUMULUS_ALTITUDE - eyeAltitude + 50.0) * 3e-2));
				float stepLength = max0(mix(intersection.y, min(intersection.y, 2e4), withinVolumeSmooth) - intersection.x);

				#if defined PROGRAM_PREPARE
					uint raySteps = uint(CLOUD_CUMULUS_SAMPLES * 0.6);
					raySteps = uint(float(raySteps) * oneMinus(abs(rayDir.y) * 0.4)); // Reduce ray steps for vertical rays
				#else
					uint raySteps = CLOUD_CUMULUS_SAMPLES;
					// raySteps = uint(raySteps * min1(0.5 + max0(stepLength - 1e2) * 5e-5)); // Reduce ray steps for vertical rays
					raySteps = uint(float(raySteps) * (withinVolumeSmooth + oneMinus(abs(rayDir.y) * 0.4))); // Reduce ray steps for vertical rays
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

				float powderFactor = sqr(LdotV * 0.5 + 0.5);

				for (uint i = 0u; i < raySteps; ++i, rayPos += rayStep) {
					if (rayPos.y < CLOUD_CUMULUS_ALTITUDE || rayPos.y > cumulusMaxAltitude) continue;

					// Compute sample cloud density
					#if defined PROGRAM_PREPARE
						float stepDensity = CloudVolumeDensity(rayPos, 3u);
					#else
						float stepDensity = CloudVolumeDensity(rayPos, 5u);
					#endif

					if (stepDensity < 1e-5) continue;

					rayHitPos += rayPos * transmittance;
					rayHitPosWeight += transmittance;

					#if defined PROGRAM_PREPARE
						vec2 lightNoise = vec2(0.5);
					#else
						// Compute light noise
						vec2 lightNoise = hash2(fract(rayPos));
					#endif

					// Compute the optical depth of sunlight through clouds
					float opticalDepthSun = CloudVolumeSunlightOD(rayPos, lightNoise.x);

					// Magic power function, looks not bad
					vec4 hitPhases = pow(phases, vec4(0.8 + 0.2 * saturate(opticalDepthSun)));

					// Compute sunlight multi-scattering
					float scatteringSun  = fastExp(-opticalDepthSun * 2.0) * hitPhases.x;
						  scatteringSun += fastExp(-opticalDepthSun * 0.8) * hitPhases.y;
						  scatteringSun += fastExp(-opticalDepthSun * 0.3) * hitPhases.z;
						  scatteringSun += fastExp(-opticalDepthSun * 0.1) * hitPhases.w;

					// Compute the optical depth of skylight through clouds
					float opticalDepthSky = CloudVolumeSkylightOD(rayPos, lightNoise.y);
					float scatteringSky = fastExp(-opticalDepthSky) + fastExp(-opticalDepthSky * 0.2) * 0.2;

					// Compute the optical depth of ground light through clouds
					float opticalDepthGround = CloudVolumeGroundLightOD(rayPos);
					float scatteringGround = fastExp(-opticalDepthGround) * isotropicPhase;

					vec2 scattering = vec2(scatteringSun + scatteringGround * cloudLightVector.y, scatteringSky + scatteringGround * 0.5);

					// Siggraph 2017's new formula
					float stepOpticalDepth = stepDensity * cumulusExtinction * stepSize;
					float stepTransmittance = max(fastExp(-stepOpticalDepth), fastExp(-stepOpticalDepth * 0.25) * 0.7);

					// Compute In-Scatter Probability
					#ifdef CLOUD_CUMULUS_ADVANCED_POWDER
						// Reference: https://github.com/qiutang98/flower/blob/main/source/shader/cloud/cloud_common.glsl
						float heightFraction = saturate((rayPos.y - CLOUD_CUMULUS_ALTITUDE) * rcp(CLOUD_CUMULUS_THICKNESS));
	
						float depthProbability = pow(min(stepDensity * 6.0, PI), remap(heightFraction, 0.3, 0.85, 0.5, 2.0)) + 0.05;
						float verticalProbability = pow(remap(heightFraction, 0.07, 0.22, 0.1, 1.0), 0.8);
						float powder = CloudPowderEffect(depthProbability, verticalProbability, powderFactor);
					#else
						float powder = 0.2 * rcp(fastExp(-stepDensity * (PI / cumulusExtinction)) * 0.85 + 0.15) - 0.2;
						powder += oneMinus(powder) * powderFactor * saturate(stepDensity * 3.0);
					#endif

					// Compute the integral of the scattering over the step
					float stepIntegral = transmittance * oneMinus(stepTransmittance);
					stepScattering += vec2(powder, powder * 0.5 + 0.5) * scattering * stepIntegral;
					transmittance *= stepTransmittance;	

					if (transmittance < minCloudTransmittance) break;
				}

				float absorption = 1.0 - transmittance;
				if (absorption > minCloudAbsorption) {
					stepScattering *= oneMinus(0.6 * wetness) * rcp(cumulusExtinction);
					rayHitPos /= rayHitPosWeight;
					FromPlanetCurvePos(rayHitPos);
					rayHitPos -= cameraPosition;

					#ifdef CLOUD_LOCAL_LIGHTING
						// Compute local lighting
						vec3 sunIlluminance, moonIlluminance;
						vec3 camera = vec3(0.0, planetRadius + eyeAltitude, 0.0);
						vec3 skyIlluminance = GetSunAndSkyIrradiance(camera + rayHitPos, worldSunVector, sunIlluminance, moonIlluminance);
						vec3 directIlluminance = sunIlluminance + moonIlluminance;
		
						skyIlluminance += lightningShading * 4e-3;
						#ifdef AURORA
							skyIlluminance += auroraShading;
						#endif
					#endif

					vec3 scattering = stepScattering.x * 12.0 * directIlluminance;
					scattering += stepScattering.y * 0.1 * skyIlluminance;

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

	// Compute mid clouds
	#if defined CLOUD_STRATOCUMULUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_MID_ALTITUDE) // Below clouds
		 || (planetIntersection && eyeAltitude > CLOUD_MID_ALTITUDE)) { // Above clouds
			float cloudDistance = (planetRadius + CLOUD_MID_ALTITUDE - r) / mu;
			vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

			vec4 cloudTemp = RenderCloudMid(cloudDistance * stratusExtinction, cloudPos.xz, rayDir.xz, LdotV, dither, phases);

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

	// Compute high clouds
	#if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_HIGH_ALTITUDE) // Below clouds
		 || (planetIntersection && eyeAltitude > CLOUD_HIGH_ALTITUDE)) { // Above clouds
			float cloudDistance = (planetRadius + CLOUD_HIGH_ALTITUDE - r) / mu;
			vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

			vec4 cloudTemp = RenderCloudHigh(cloudDistance * cirrusExtinction, cloudPos.xz, rayDir.xz, LdotV, dither, phases);

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