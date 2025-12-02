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
	vec2 curlNoise = texture(curlNoiseTex, rayPos * 5e-5).xy * 0.05;
	vec2 position = (rayPos - windOffset) * 2e-4 + curlNoise;

	float density = 0.0;

	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */
	{
		float coverage = CLOUD_CI_COVERAGE - 0.4 + texture(noisetex, position * 0.02).z;
		coverage = saturate(coverage - texture(cloudMapTex, (position * 0.01)).x);

		if (coverage > 0.25) {
			vec2 p = position + coverage * 0.5 - windOffset * 1e-4;
			float cirrus = textureBicubic(cirroLutTex, p * 0.3).y;
			cirrus *= smoothstep(0.25, 0.65, coverage) * 0.5;

			density += sqr(cirrus);
		}
	}
	#endif
	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */
	{
		float coverage = CLOUD_CC_COVERAGE - saturate(texture(noisetex, position * 0.01).z * 1.75);
		coverage = saturate(texture(cloudMapTex, (position * 0.02)).y + coverage);

		if (coverage > 0.3) {
			vec2 p = position + coverage * 0.5 - windOffset * 1e-4;
			float cirrocumulus = sqr(textureBicubic(cirroLutTex, p * 0.3).x);

			cirrocumulus *= saturate(cirrocumulus + coverage);
			cirrocumulus *= smoothstep(0.3, 0.9, coverage);

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
	float GetVerticalProfile(in float heightFraction, in float cloudType) {
		float stratus = saturate(heightFraction * 16.0) * linearstep(0.2, 0.1, heightFraction);
		float stratocumulus = saturate(heightFraction * 6.0) * linearstep(0.6, 0.2, heightFraction);
		float cumulus = saturate(heightFraction * 8.0) * linearstep(1.0, 0.7, heightFraction);

		float verticalProfile = mix(stratus, stratocumulus, curve(saturate(cloudType * 2.0)));
		return mix(almostUnitIdentity(verticalProfile), cumulus, saturate(cloudType * 2.0 - 1.0));
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
	vec2 stepEdge = mix(vec2(1.1, 1.6) * oms(CLOUD_CU_COVERAGE), vec2(0.1, 0.7), sqr(wetness));
	float coverage = linearstep(stepEdge.x, stepEdge.y, cloudMap.x);

	// Vertical profile
	float type = smoothstep(0.4 - wetness * 0.2, 1.0, cloudMap.y) * coverage;
	float gradient = GetVerticalProfile(heightFraction, type);

	dimensionalProfile = saturate(gradient * coverage);
	// dimensionalProfile = saturate(gradient + coverage - 1.0);
	if (dimensionalProfile < 0.05) return 0.0;

	rayPos -= windDir * cumulusTopOffset * heightFraction;
	vec3 position = rayPos * 3e-4;

	#if 0
	vec2 billowyNoise = texture(baseNoiseTex, fract(position)).xy;

	// Blend between HF and LF according to dimensionalProfile
	float baseNoise = mix(billowyNoise.x, billowyNoise.y, approxSqrt(dimensionalProfile));
	#else
	float baseNoise = texture(baseNoiseTex, position).x;
	#endif

	float cloudDensity = ValueErosion(dimensionalProfile, oms(baseNoise) * 0.75);
	if (cloudDensity < cloudEpsilon) return 0.0;

	// Detail erosion
	float detailNoise = 0.25;
	float heightFade = sqr(1.0 - heightFraction);

	#if !defined PASS_SKY_MAP
	if (detail) {
		// vec3 curlNoise = texture(curlNoiseTex, position.xz * 2.0).xyz;
		position += baseNoise * heightFade * 0.2 * windDir + windOffset * 1e-4;

		detailNoise = sqr(texture(detailNoiseTex, position * 8.0).x);

		// Transition from wispy shapes to billowy shapes over height
		// detailNoise = mix(1.0 - detailNoise, detailNoise, saturate(heightFraction * 8.0));
	}
	#endif

	detailNoise *= mix(0.2, 0.5, heightFade);
	// cloudDensity = ValueErosion(cloudDensity, detailNoise);
	cloudDensity = saturate(cloudDensity - detailNoise);

	// Density profile
	return approxSqrt(cloudDensity) * remap(heightFraction, 0.1, 0.2, 0.2, 1.0);
}

#endif // INCLUDE_CLOUDS_SHAPE