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

	float cloudShadow = 0.0;
	// #if defined CLOUD_ALTOSTRATUS
	// {	// Start from the cloud intersection plane and move towards the light vector.
	// 	float shadowAltitude = CLOUD_MID_ALTITUDE - rayPos.y;
	// 	if (shadowAltitude > 1e-6) {
	// 		vec2 planePos = rayPos.xz + cloudLightVector.xz * (shadowAltitude / cloudLightVector.y);
	// 		cloudShadow += CloudMidDensity(planePos) * (5e2 * stratusExtinction);
	// 	}
	// }
	// #endif
	// #if defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
	// {	// Start from the cloud intersection plane and move towards the light vector.
	// 	float shadowAltitude = CLOUD_HIGH_ALTITUDE - rayPos.y;
	// 	if (shadowAltitude > 1e-6) {
	// 		vec2 planePos = rayPos.xz + cloudLightVector.xz * (shadowAltitude / cloudLightVector.y);
	// 		cloudShadow += CloudHighDensity(planePos) * (3e2 * cirrusExtinction);
	// 	}
	// }
	// #endif

	#ifdef CLOUD_CUMULUS
	const float transmittanceCoeff = 0.25 * CLOUD_CU_THICKNESS * cumulusExtinction;

	{	// Start from the cloud intersection plane and move towards the light vector.
		float shadowAltitude = (CLOUD_CU_ALTITUDE + 0.225 * CLOUD_CU_THICKNESS) - rayPos.y;
		if (shadowAltitude > 1e-6) {
			vec3 cloudPos = rayPos + cloudLightVector * (shadowAltitude / cloudLightVector.y);
			#if 1
				cloudShadow += CloudVolumeSunlightOD(cloudPos, 0.5) * transmittanceCoeff;
			#else
				cloudShadow += CloudVolumeDensity(cloudPos, false) * transmittanceCoeff;
			#endif
		}
	}
	{	// Start from the cloud intersection plane and move towards the light vector.
		float shadowAltitude = (CLOUD_CU_ALTITUDE + 0.275 * CLOUD_CU_THICKNESS) - rayPos.y;
		if (shadowAltitude > 1e-6) {
			vec3 cloudPos = rayPos + cloudLightVector * (shadowAltitude / cloudLightVector.y);
			#if 0
				cloudShadow += CloudVolumeSunlightOD(cloudPos, 0.5) * transmittanceCoeff;
			#else
				cloudShadow += CloudVolumeDensity(cloudPos, false) * transmittanceCoeff;
			#endif
		}
	}
	#endif

	float timeFade = sqr(remap(0.05, 0.1, cloudLightVector.y));
	cloudShadow = oms(timeFade) + exp2(-cloudShadow) * timeFade;

	return cloudShadow;
}
#endif