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
float ValueErosion(in float value, in float oldMin) {
    return saturate((value - oldMin) / (1.0 - oldMin));
}

float CloudMidDensity(in vec2 rayPos) {
	return 0.0;
}

// Adapted from [Schneider, 2022]
float CloudHighDensity(in vec2 rayPos) {
	// Wind field
	const float windAngle = radians(30.0);
	const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_HIGH_WIND_SPEED;
	vec2 windOffset = windVelocity * worldTimeCounter;

	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curlNoise = texture(curlNoiseTex, rayPos * 5e-5).xy * 0.1;
	vec2 position = (rayPos - windOffset) * 2e-4 + curlNoise;

	float density = 0.0;

	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */
	{
		float coverage = CLOUD_CI_COVERAGE - 0.3 + texture(noisetex, position * 0.01).z;
		coverage = saturate(coverage - texture(cloudMapTex, (position * 0.01)).y);

		if (coverage > 0.25) {
			vec2 p = position + coverage * 0.5 - windOffset * 1e-4;
			float cirrus = textureBicubic(cirroLutTex, p * 0.3).y;

			cirrus *= saturate(cirrus + coverage);
			cirrus *= sqr(linearstep(0.25, 1.0, coverage));

			density += cirrus;
		}
	}
	#endif
	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */
	{
		float coverage = CLOUD_CC_COVERAGE - saturate(texture(noisetex, position * 0.01).z * 2.0);
		coverage = saturate(texture(cloudMapTex, (position * 0.01)).x + coverage);

		if (coverage > 0.35) {
			vec2 p = position + coverage * 0.5 - windOffset * 1e-4;
			float cirrocumulus = sqr(textureBicubic(cirroLutTex, p * 0.3).x);

			cirrocumulus *= saturate(cirrocumulus + coverage);
			cirrocumulus *= linearstep(0.35, 1.0, coverage);

			density += cirrocumulus;
		}
	}
	#endif

	return density;
}

//================================================================================================//

#if 0
	float GetVerticalProfile(in float heightFraction, in float cloudType) {
		return texture(verticalLut, vec2(cloudType, heightFraction)).x;
	}
#else
	float GetVerticalProfile(in float h, in float t) {
		float stratus = linearstep(0.1, 0.15, h) * linearstep(0.25, 0.15, h);
		float stratocumulus = saturate(h * 6.0) * linearstep(0.6, 0.2, h);
		float cumulus = saturate(h * 8.0) * linearstep(1.0, 0.75, h);

		float gradient = mix(stratus, stratocumulus, smoothstep(0.0, 0.5, t));
		return mix(gradient, cumulus, smoothstep(0.5, 1.0, t));
	}
#endif

float CloudVolumeDensity(in vec3 rayPos, out float heightFraction, out float dimensionalProfile, in bool detail) {
	// Remap the height of the clouds to the range of [0, 1]
	heightFraction = saturate((length(rayPos) - cumulusBottomRadius) * rcp(cumulusThickness));

	// Wind field
	const float windAngle = radians(45.0);
	const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
	const vec3 windVelocity = windDir * CLOUD_LOW_WIND_SPEED;
	vec3 windOffset = windVelocity * worldTimeCounter;

	rayPos -= windOffset;
	rayPos.xz += cameraPosition.xz;

	// Sample cloud map
	vec2 cloudMap = texture(cloudMapTex, (rayPos.xz * rcp(cloudMapExtend))).xy;

	// Coveage profile
	vec2 stepEdge = mix(vec2(0.6, 1.0) - CLOUD_CU_COVERAGE * 0.4, vec2(0.1, 0.5), sqr(wetness));
	float coverage = linearstep(stepEdge.x, stepEdge.y, cloudMap.x);
	coverage *= linearstep(stepEdge.x * 1.2, stepEdge.y * 0.7, texture(noisetex, rayPos.xz * rcp(512e3)).z);

	// Vertical profile
	float type = curve(cloudMap.y) * coverage;
	float gradient = GetVerticalProfile(heightFraction, type);

	// dimensionalProfile = gradient * coverage;
	dimensionalProfile = saturate(gradient + coverage - 1.0);
	if (dimensionalProfile < 0.1) return 0.0;

	vec3 noisePos = (rayPos - windDir * heightFraction * cumulusTopOffset) * rcp(3e3);
		noisePos.y *= 1.25;

	#if 0
	vec2 billowyNoise = texture(baseNoiseTex, fract(noisePos)).xy;

	// Blend between HF and LF according to dimensionalProfile
	float baseNoise = mix(billowyNoise.x, billowyNoise.y, approxSqrt(dimensionalProfile));
	#else
	float baseNoise = texture(baseNoiseTex, noisePos).x;
	#endif

	// See [Schneider, 2022]
	float cloudDensity = dimensionalProfile + (baseNoise - 1.0);
	if (cloudDensity < cloudEpsilon) return 0.0;

	float heightFade = smoothstep(0.4, 0.2, heightFraction);

	// Detail erosion
	float detailNoise = 0.125;

	#if !defined PASS_SKY_MAP
	if (detail) {
		// vec3 curlNoise = texture(curlNoiseTex, noisePos.xz * 2.0).xyz;
		noisePos -= baseNoise * 0.1 * windDir + windOffset * 1e-4;

		detailNoise = texture(detailNoiseTex, noisePos * 8.0).x;

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = sqr(mix(0.75 - detailNoise * 0.5, detailNoise, heightFade)) * 0.5;
	}
	#endif

	cloudDensity = ValueErosion(cloudDensity, detailNoise);
	// cloudDensity = saturate(cloudDensity - detailNoise * oms(cloudDensity));

	// Density profile
	return saturate(cloudDensity * mix(CLOUD_CU_DENSITY_T, CLOUD_CU_DENSITY_B, heightFade));
}

#endif // INCLUDE_CLOUDS_SHAPE