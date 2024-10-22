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

#if !defined INCLUDE_CLOUDS_LAYERS
#define INCLUDE_CLOUDS_LAYERS

#include "Common.glsl"

//================================================================================================//

float GetSmoothNoise(in vec2 coord) {
    vec2 whole = floor(coord);
    vec2 part = curve(coord - whole);

	ivec2 texel = ivec2(whole);

	float s0 = texelFetch(noisetex, texel % 256, 0).x;
	float s1 = texelFetch(noisetex, (texel + ivec2(1, 0)) % 256, 0).x;
	float s2 = texelFetch(noisetex, (texel + ivec2(0, 1)) % 256, 0).x;
	float s3 = texelFetch(noisetex, (texel + ivec2(1, 1)) % 256, 0).x;

    return mix(mix(s0, s1, part.x), mix(s2, s3, part.x), part.y);
}

float Calculate3DNoiseSmooth(in vec3 position) {
	vec3 p = floor(position);
	vec3 b = curve(position - p);

	ivec2 texel = ivec2(p.xy + 97.0 * p.z);

	vec2 s0 = texelFetch(noisetex, texel % 256, 0).xy;
	vec2 s1 = texelFetch(noisetex, (texel + ivec2(1, 0)) % 256, 0).xy;
	vec2 s2 = texelFetch(noisetex, (texel + ivec2(0, 1)) % 256, 0).xy;
	vec2 s3 = texelFetch(noisetex, (texel + ivec2(1, 1)) % 256, 0).xy;

	vec2 rg = mix(mix(s0, s1, b.x), mix(s2, s3, b.x), b.y);

	return mix(rg.x, rg.y, b.z);
}

float CloudPlaneDensity(in vec2 rayPos) {
	vec2 shift = cloudWindLayer2 * CLOUD_WIND_SPEED;

	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.04;
	curl += texture(noisetex, rayPos * 1e-5).xy * 0.02;

	float localCoverage = GetSmoothNoise(rayPos * 3e-5 + curl - shift * 0.3);
	float density = 0.0;

	#ifdef CLOUD_STRATOCUMULUS
	/* Stratocumulus clouds */ if (localCoverage > 0.5) {
		vec2 position = (rayPos * 3e-4 - shift + curl) * 5e-3;

		float stratocumulus = texture(noisetex, position * 8.5).z, weight = 0.5;

		// Stratocumulus FBM
		for (uint i = 0u; i < 5u; ++i, weight *= 0.47) {
			stratocumulus += weight * texture(noisetex, position).x;
			position = position * (2.6 + approxSqrt(float(i))) + (stratocumulus - shift) * 0.012;
		}

		if (stratocumulus > 1e-5) density += sqr(saturate(stratocumulus * 1.8 - 1.5)) * saturate(localCoverage * 1.6 - 0.9);
	}
	#endif
	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */ if (density < 0.1) {
		shift = cloudWindLayer3 * CLOUD_WIND_SPEED;
		vec2 position = rayPos * 9e-5 - shift + curl * 2.0;

		float baseCoverage = curve(texture(noisetex, position * 0.08).z * 0.65 + 0.1);
		baseCoverage *= max0(1.07 - texture(noisetex, position * 0.003).y * 1.4);

		// The base shape of the cirrocumulus clouds using perlin-worley noise
		float cirrocumulus = 0.5 * texture(noisetex, position * vec2(0.4, 0.16)).z;
		cirrocumulus += texture(noisetex, (position - shift) * 0.9).z - 0.3;
		cirrocumulus = saturate(cirrocumulus - density - 0.014);

		cirrocumulus *= clamp(baseCoverage - saturate(localCoverage * 1.4 - 0.5), 0.0, 0.25) * 0.6;
		if (cirrocumulus > 1e-6) {
			position.x += (cirrocumulus - shift.x) * 0.2;

			#if !defined PROGRAM_PREPARE
				// Detail shape of the cirrocumulus clouds
				cirrocumulus += 0.016 * texture(noisetex, position * 3.0).z;
				cirrocumulus += 0.01 * texture(noisetex, position * 5.0 + curl).z - 0.026;
			#endif

			density += cube(saturate((cirrocumulus) * 4.8));
		}
	}
	#endif
	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */ if (density < 0.1) {
		shift = cloudWindLayer4 * CLOUD_WIND_SPEED;
		vec2 position = rayPos * 4e-7 - shift * 2e-3 + curl * 2e-3;
		const vec2 angle = cossin(PI * 0.2);
		const mat2 rot = mat2(angle, -angle.y, angle.x);

		float weight = 0.6;
		float cirrus = texture(noisetex, position * vec2(0.9, 1.1)).x;

		// Cirrus FBM
		for (uint i = 1u; i < 5u; ++i, weight *= 0.45) {
			position = rot * (position - shift * 2e-3) * vec2(2.3, 2.5 + approxSqrt(i));
			position += (cirrus + curl) * 4e-3;
			cirrus += texture(noisetex, position).x * weight;
		}
		cirrus -= saturate(localCoverage * 1.65 - 0.6);

		if (cirrus > 1e-5) density += sqr(0.18 * max0(cirrus * 0.9 - 0.78 - density) * cirrus);
	}
	#endif

	return density;
}

float remap(float value, float orignalMin, float orignalMax, float newMin, float newMax) {
    return newMin + saturate((value - orignalMin) / (orignalMax - orignalMin)) * (newMax - newMin);
}

#if 0
	float CloudVolumeDensity(in vec3 rayPos, in uint octCount) {
		float baseCoverage = texture(noisetex, rayPos.xz * 1e-6 - cloudWindLayer1.xz * 2e-5).x;
		// baseCoverage = saturate(baseCoverage * 1.2 - 0.2);
		if (baseCoverage < 1e-6) return 0.0;

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - CLOUD_CUMULUS_ALTITUDE) * rcp(CLOUD_CUMULUS_THICKNESS));

		vec3 shift = CLOUD_WIND_SPEED * cloudWindLayer1 * 2.5;
		vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

		vec4 lowFreqNoises = texture(depthtex2, position * 0.2);
		float shape = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));

		shape = remap(lowFreqNoises.x - 1.0, 1.0, shape) + (baseCoverage - 0.75) * 0.7;

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 4.0) * saturate(6.0 - heightFraction * 6.0);

		shape *= gradienShape * CLOUD_CUMULUS_COVERAGE * (0.9 + wetness * 0.1);
		shape -= heightFraction * 0.5 + 0.3;

		if (shape > 1e-6 && octCount > 3u) {
			vec2 curlNoise = texture(noisetex, position.xz * 5e-2).xy;
			position.xy += curlNoise * 0.25 * oneMinus(heightFraction);

			vec4 highFreqNoises = texture(colortex15, position * 6.0 - shift);
			float detail = dot(highFreqNoises, vec4(0.8, 0.32, 0.12, 0.04));

			// Transition from wispy shapes to billowy shapes over height
			detail = mix(detail, 1.0 - detail, saturate(heightFraction * 10.0));

			shape = remap(detail * 0.06, 0.3, shape);
		} else {
			shape = remap(0.03, 0.3, shape);
		}

		// shape *= saturate(0.01 + heightFraction * 1.15) * saturate(5.0 - heightFraction * 5.0);

		return shape;
	}
#elif 1
	float CloudVolumeDensity(in vec3 rayPos, in uint octCount) {
		float baseCoverage = texture(noisetex, rayPos.xz * 1e-6 - cloudWindLayer1.xz * 2e-5).x;
		// baseCoverage = saturate(baseCoverage * 1.2 - 0.2);
		if (baseCoverage < 1e-6) return 0.0;

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - CLOUD_CUMULUS_ALTITUDE) * rcp(CLOUD_CUMULUS_THICKNESS));

		vec3 shift = CLOUD_WIND_SPEED * cloudWindLayer1 * 2.5;
		vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

		vec4 lowFreqNoises = texture(depthtex2, position * 0.2);
		float shape = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));

		shape = remap(lowFreqNoises.x - 1.0, 1.0, shape) + baseCoverage * 0.7;

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 2.4) * saturate(6.0 - heightFraction * 6.0);

		shape *= gradienShape * CLOUD_CUMULUS_COVERAGE * (0.8 + wetness * 0.07);
		shape -= heightFraction * 0.4 + 0.63;

		if (shape > 1e-6 && octCount > 3u) {
			vec2 curlNoise = texture(noisetex, position.xz * 5e-2).xy;
			position.xy += curlNoise * 0.25 * oneMinus(heightFraction);

			vec4 highFreqNoises = texture(colortex15, position * 6.0 - shift);
			float detail = dot(highFreqNoises, vec4(0.8, 0.32, 0.12, 0.04));

			// Transition from wispy shapes to billowy shapes over height
			detail = mix(detail, 1.0 - detail, saturate(heightFraction * 10.0));

			shape = remap(detail * 0.04, 0.3, shape);
		} else {
			shape = remap(0.02, 0.3, shape);
		}

		// shape *= saturate(0.01 + heightFraction * 1.15) * saturate(5.0 - heightFraction * 5.0);

		return shape;
	}
#else
	float CloudVolumeDensity(in vec3 rayPos, in uint octCount) {
		float baseCoverage = texture(noisetex, rayPos.xz * 1e-6 - cloudWindLayer1.xz * 2e-5).x;
		// baseCoverage = saturate(baseCoverage * 1.2 - 0.2);
		if (baseCoverage < 1e-6) return 0.0;

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - CLOUD_CUMULUS_ALTITUDE) * rcp(CLOUD_CUMULUS_THICKNESS));

		vec3 shift = CLOUD_WIND_SPEED * cloudWindLayer1 * 2.5;
		vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

		vec4 lowFreqNoises = texture(depthtex2, position * 0.2);
		float shape = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));

		shape = remap(lowFreqNoises.x - 1.0, 1.0, shape);
		shape = remap(1.0 - baseCoverage, 1.0, shape);

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 4.0) * saturate(5.0 - heightFraction * 5.0);

		shape *= gradienShape * CLOUD_CUMULUS_COVERAGE * (0.74 + wetness * 0.06);
		shape -= heightFraction * 0.4 + 0.16;

		if (shape > 1e-6 && octCount > 3u) {
			vec2 curlNoise = texture(noisetex, position.xz * 5e-2).xy;
			position.xy += curlNoise * 0.25 * oneMinus(heightFraction);

			vec4 highFreqNoises = texture(colortex15, position * 6.0 - shift);
			float detail = dot(highFreqNoises, vec4(0.8, 0.32, 0.12, 0.04));

			// Transition from wispy shapes to billowy shapes over height
			detail = mix(detail, 1.0 - detail, saturate(heightFraction * 10.0));

			shape = remap(detail * 0.08, 0.4, shape);
		} else {
			shape = remap(0.04, 0.4, shape);
		}

		// shape *= saturate(0.01 + heightFraction * 1.15) * saturate(5.0 - heightFraction * 5.0);

		return shape;
	}
#endif

#endif