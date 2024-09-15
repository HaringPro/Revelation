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

float CalculateCloudShadows(in vec3 rayPos) {
	vec3 origin = rayPos + vec3(0.0, planetRadius, 0.0);
	vec2 planePos = RaySphereIntersection(origin, cloudLightVector, planetRadius + CLOUD_PLANE_ALTITUDE).y * cloudLightVector.xz + rayPos.xz;

	#if defined CLOUD_STRATOCUMULUS || defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		float cloudDensity = CloudPlaneDensity(planePos) * 1e3 * cirrusExtinction;
	#else
		float cloudDensity = 0.0;
	#endif

	#ifdef CLOUD_CUMULUS
		vec3 cloudPos = RaySphereIntersection(origin, cloudLightVector, planetRadius + 0.5 * (CLOUD_CUMULUS_ALTITUDE + cumulusMaxAltitude)).y * cloudLightVector + rayPos;
		cloudDensity += CloudVolumeDensitySmooth(cloudPos) * CLOUD_CUMULUS_THICKNESS * cumulusExtinction * 0.1;
	#endif

	// cloudDensity = mix(0.4, cloudDensity, saturate(approxSqrt(abs(cloudLightVector.y) * 2.0)));

	return exp2(-0.5 * cloudDensity);
}