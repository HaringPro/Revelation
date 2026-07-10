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

#if !defined INCLUDE_CLOUDS_SHAPE
#define INCLUDE_CLOUDS_SHAPE

#include "/lib/atmosphere/clouds/Common.glsl"

//================================================================================================//

// [Schneider, 2023]
float ValueErosion(float value, float oldMin) {
	return saturate((value - oldMin) / (1.0 - oldMin));
}

float CloudHighDensity(vec2 rayPos) {
	// Wind field
	const vec2 windVelocity = vec2(cos(cloudLayer2.windAngle), sin(cloudLayer2.windAngle)) * cloudLayer2.windSpeed;
	vec2 windOffset = windVelocity * worldTimeCounter;

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	rayPos -= windOffset;
	rayPos += cameraPosition.xz;

    float coverage = texture(cloudMapTex, rayPos * 3e-6).x;
    if (coverage < 0.4) return 0.0;

	vec2 curlNoise = texture(curlNoise2D, rayPos * 4e-5).xy * 0.25;

	vec2 position = rayPos * 2e-4 + curlNoise;
    position *= goldenRotate;

    vec2 lutPos = position * 0.3 - coverage * 0.075;
    vec3 lutValue = texture(cirroLutTex, lutPos).xyz;

    // Sharpen lutValue with low coverage
    lutValue = mix(pow4(lutValue), lutValue, coverage);

    lutValue.xy *= sqr(linearstep(0.4, 1.0, coverage));
    lutValue.z *= smoothstep(0.4, 0.9, coverage);

	float density = 0.0;

	// Cirrus clouds
	#ifdef CLOUD_CI
	{
		float coverage = texture(cloudMapTex, position * 0.004).y;
		coverage = CLOUD_CI_COVERAGE + 0.5 - coverage;
        coverage = sqr(linearstep(0.5, 1.0, coverage));

        float cirrus = lutValue.x;
        density = cirrus * coverage;
	}
	#endif

	// Cirrostratus clouds
	#ifdef CLOUD_CS
	{
		float coverage = texture(cloudMapTex, position * 0.004).y;
		coverage = CLOUD_CS_COVERAGE - 0.5 + coverage;
        coverage = sqr(linearstep(0.5, 1.25, coverage));

        float cirrostratus = lutValue.y;
        density += cirrostratus * coverage;
	}
	#endif

	// Cirrocumulus clouds
	#ifdef CLOUD_CC
	{
		float coverage = texture(noisetex, position * 0.002).z;
        coverage += texture(noisetex, position * 0.006).z * 0.5;
		coverage = CLOUD_CC_COVERAGE - 1.0 + coverage;
        coverage = smoothstep(0.5, 1.0, coverage);

        float cirrocumulus = smoothstep(0.1, 1.0, lutValue.z);
        density += cirrocumulus * coverage;
	}
	#endif

	return density;
}

//================================================================================================//

#if 0
	float GetVerticalProfile(float heightFraction, float cloudType) {
		return texture(verticalLut, vec2(cloudType, heightFraction)).x;
	}
#else
	float GetVerticalProfile(float h, float t) {
		float stratus = saturate(h * 16.0) * linearstep(0.2, 0.1, h);
		float stratocumulus = saturate(h * 6.0) * linearstep(0.6, 0.2, h);
		float cumulus = saturate(h * 8.0) * linearstep(1.0, 0.6, h);

		float gradient = mix(stratus, stratocumulus, smoothstep(0.0, 0.5, t));
		return mix(gradient, cumulus, smoothstep(0.5, 1.0, t));
	}
#endif

float CloudVolumeDensity(vec3 rayPos, float heightFraction, out float dimensionalProfile, bool detail) {
	// Wind field
	const vec3 windDir = vec3(cos(cloudLayer0.windAngle), 0.5, sin(cloudLayer0.windAngle));
	const vec3 windVelocity = windDir * cloudLayer0.windSpeed;
	vec3 windOffset = windVelocity * worldTimeCounter;

	rayPos -= windOffset;
	rayPos.xz += cameraPosition.xz;

	// Sample cloud map
	vec2 cloudMap = texture(cloudMapTex, (rayPos.xz * rcp(cloudMapExtend))).xy;

	// Coveage profile
	vec2 stepEdge = mix(vec2(0.5, 0.95) - CLOUD_CU_COVERAGE * 0.4, vec2(0.1, 0.4), sqr(wetness));
	float coverage = linearstep(stepEdge.x, stepEdge.y, cloudMap.x);

	float localCoverage = texture(noisetex, rayPos.xz * rcp(512e3) + 0.75).z;
	coverage *= linearstep(stepEdge.x * 1.1, stepEdge.y * 0.8, localCoverage);

	// Vertical profile
	float type = cloudMap.y * approxSqrt(coverage);
	// heightFraction = ValueErosion(heightFraction, oms(cloudMap.y) * 0.3);
	float gradient = GetVerticalProfile(heightFraction, type);

	#if 0
	dimensionalProfile = (gradient * coverage);
	#else
	dimensionalProfile = saturate(gradient + coverage - 1.0);
	#endif
	if (dimensionalProfile < 0.1) return 0.0;

	vec3 noisePos = (rayPos - windDir * heightFraction * cloudLayer0.thickness * 0.5) * rcp(2e3);
	noisePos.y += dot(noisePos.xz, vec2(0.2, 0.3)); // Reduce repetition pattern

	// Add curl noise
	#if !defined PASS_SKY_MAP
	if (detail) {
		vec3 curlNoise = texture(curlNoise3D, noisePos * vec3(2.0, 3.0, 2.0)).xyz;
		noisePos += curlNoise * gradient * oms(coverage) * 0.4;
	}
	#endif

	#if 0
	vec2 billowyNoise = texture(baseNoiseTex, fract(noisePos)).xy;

	// Blend between HF and LF according to dimensionalProfile
	float baseNoise = mix(billowyNoise.x, billowyNoise.y, approxSqrt(dimensionalProfile));
	#else
	float baseNoise = texture(baseNoiseTex, noisePos).x;
	#endif

	// See [Schneider, 2022]
	float cloudDensity = dimensionalProfile + (baseNoise - 1.0) * 0.75;
	if (cloudDensity < cloudDensityEpsilon) return 0.0;

	float heightFade = smoothstep(0.1, 0.5, heightFraction);

	// Detail erosion
	// float detailNoise = 0.1;

	// #if !defined PASS_SKY_MAP
	// if (detail) {
	// 	noisePos -= baseNoise * 0.1 * windDir + windOffset * 1e-4;

	// 	detailNoise = texture(detailNoiseTex, noisePos * 8.0).x;

	// 	// Transition from wispy shapes to billowy shapes over height
	// 	detailNoise = sqr(mix(detailNoise, 0.75 - detailNoise * 0.5, heightFade)) * 0.4;
	// }
	// #endif

	// cloudDensity = ValueErosion(cloudDensity, detailNoise);
	// cloudDensity = saturate(cloudDensity - detailNoise * oms(cloudDensity));

	// Density profile
	cloudDensity *= mix(1.0, inversesqrt(cloudDensity), heightFraction);
	return cloudDensity * mix(CLOUD_CU_DENSITY_B, CLOUD_CU_DENSITY_T, heightFade);
}

#endif // INCLUDE_CLOUDS_SHAPE
