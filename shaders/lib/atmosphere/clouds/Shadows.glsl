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

#include "/lib/atmosphere/clouds/Common.glsl"

//================================================================================================//

vec3 CloudShadowToWorldPos(in vec2 rayPos) {
	rayPos = rayPos * 2.0 - 1.0;

	// Scale
	rayPos *= CLOUD_SHADOW_DISTANCE;

	// Shadow view space to world space
	return mat3(shadowModelViewInverse) * vec3(rayPos, 0.0);
}

vec2 WorldToCloudShadowPos(in vec3 rayPos) {
	// World space to shadow view space
	rayPos = mat3(shadowModelView) * rayPos;

	// Scale
	rayPos.xy *= rcp(CLOUD_SHADOW_DISTANCE);

	return rayPos.xy * 0.5 + 0.5;
}

//================================================================================================//

#if defined PASS_CLOUD_SM
#include "/lib/atmosphere/clouds/Shape.glsl"

float CalculateCloudShadows(in vec3 rayPos) {
	const uint steps = CLOUD_SHADOW_SAMPLES;

	vec3 cloudViewerPos = vec3(cameraPosition.xz, viewerHeight).xzy;
	rayPos += cloudViewerPos;

	vec2 intersection = RaySphericalShellIntersection(rayPos, cloudLightVector, cumulusBottomRadius, cumulusTopRadius);
	float stepLength = (intersection.y - intersection.x) * rcp(float(steps));
	vec3 rayStep = cloudLightVector * stepLength;

	rayPos += cloudLightVector * intersection.x;
	rayPos += rayStep * InterleavedGradientNoiseTemporal(gl_FragCoord.xy);

	float opticalDepth = 0.0;

	// Raymarch along the light vector
	for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
		opticalDepth += CloudVolumeDensity(rayPos, false);
		if (opticalDepth > float(steps) * 0.25) break;
	}

	float cloudShadow = exp2(-(cumulusExtinction * rLOG2) * opticalDepth * stepLength);

	float timeFade = remap(0.05, 0.1, cloudLightVector.y);
	return oms(timeFade) + cloudShadow * timeFade;
}
#endif