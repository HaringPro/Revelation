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

vec2 WorldToCloudShadowCoord(in vec3 rayPos) {
	// World space to shadow view space
	rayPos = mat3(shadowModelView) * rayPos;

	// Scale
	rayPos.xy *= rcp(min(CLOUD_SHADOW_DISTANCE, CSD_INF));

	// Distortion
	rayPos.xy *= rcp(1.0 + length(rayPos.xy));

	return rayPos.xy * 0.5 + 0.5;
}

vec3 CloudShadowToWorldCoord(in vec2 rayPos) {
	rayPos = rayPos * 2.0 - 1.0;

	// Distortion
	rayPos *= rcp(1.0 - length(rayPos));

	// Scale
	rayPos *= min(CLOUD_SHADOW_DISTANCE, CSD_INF);

	// Shadow view space to world space
	return mat3(shadowModelViewInverse) * vec3(rayPos, 0.0);
}

//================================================================================================//

#ifdef PASS_SKY_VIEW
float CalculateCloudShadows(in vec3 rayPos) {
	const uint steps = CLOUD_SHADOW_SAMPLES;

	rayPos += cameraPosition;

	vec2 intersection = RaySphericalShellIntersection(rayPos + vec3(0.0, planetRadius, 0.0), cloudLightVector, planetRadius + CLOUD_CU_ALTITUDE, planetRadius + cumulusMaxAltitude);
	float stepLength = (intersection.y - intersection.x) * rcp(float(steps));

	rayPos += cloudLightVector * intersection.x;
	vec3 rayStep = cloudLightVector * stepLength;

	float transmittance = 0.0;

	// Raymarch along the light vector
	for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
		transmittance += CloudVolumeDensity(rayPos, false);
		if (transmittance > 2.0) break;
	}

	float cloudShadow = fastExp(-transmittance * stepLength);

	float timeFade = sqr(remap(0.05, 0.1, cloudLightVector.y));
	return oms(timeFade) + cloudShadow * timeFade;
}
#endif