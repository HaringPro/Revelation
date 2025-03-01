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

#include "/lib/atmosphere/clouds/Layers.glsl"

//================================================================================================//

vec2 WorldToCloudShadowCoord(in vec3 rayPos) {
	// World space to shadow view space
	rayPos = mat3(shadowModelView) * rayPos;

	// Scale
	rayPos.xy *= rcp(min(CLOUD_SHADOW_DISTANCE, INF));

	// Distortion
	rayPos.xy *= rcp(1.0 + length(rayPos.xy));

	return rayPos.xy * 0.5 + 0.5;
}

vec3 CloudShadowToWorldCoord(in vec2 rayPos) {
	rayPos = rayPos * 2.0 - 1.0;

	// Distortion
	rayPos *= rcp(1.0 - length(rayPos));

	// Scale
	rayPos *= min(CLOUD_SHADOW_DISTANCE, INF);

	// Shadow view space to world space
	return mat3(shadowModelViewInverse) * vec3(rayPos, 0.0);
}

//================================================================================================//

#ifdef PASS_SKY_VIEW
float CalculateCloudShadows(in vec3 rayPos) {
	rayPos += cameraPosition;

	float cloudShadow = 1.0;
	#if defined CLOUD_ALTOSTRATUS
	{	// Start from the cloud intersection plane and move towards the light vector.
		float shadowAltitude = CLOUD_MID_ALTITUDE - rayPos.y;
		if (shadowAltitude > 1e-6) {
			vec2 planePos = rayPos.xz + cloudLightVector.xz * (shadowAltitude / cloudLightVector.y);
			cloudShadow = exp2(-CloudMidDensity(planePos) * (5e2 * stratusExtinction));
		}
	}
	#endif
	#if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
	{	// Start from the cloud intersection plane and move towards the light vector.
		float shadowAltitude = CLOUD_HIGH_ALTITUDE - rayPos.y;
		if (shadowAltitude > 1e-6) {
			vec2 planePos = rayPos.xz + cloudLightVector.xz * (shadowAltitude / cloudLightVector.y);
			cloudShadow = exp2(-CloudHighDensity(planePos) * (3e2 * cirrusExtinction));
		}
	}
	#endif

	#ifdef CLOUD_CUMULUS
	{	// Start from the cloud intersection plane and move towards the light vector.
		float shadowAltitude = (CLOUD_CU_ALTITUDE + 0.33 * CLOUD_CU_THICKNESS) - rayPos.y;
		if (shadowAltitude > 1e-6) {
			vec3 cloudPos = rayPos + cloudLightVector * (shadowAltitude / cloudLightVector.y);
			#if 0
				cloudShadow *= exp2(-CloudVolumeSunlightOD(cloudPos, 0.5) * (0.2 * CLOUD_CU_THICKNESS * cumulusExtinction));
			#else
				cloudShadow *= exp2(-CloudVolumeDensity(cloudPos, true) * (0.2 * CLOUD_CU_THICKNESS * cumulusExtinction));
			#endif
		}
	}
	#endif

	float timeFade = sqr(remap(0.08, 0.16, cloudLightVector.y));
	cloudShadow = oneMinus(timeFade) + cloudShadow * timeFade;

	return cloudShadow;
}
#endif