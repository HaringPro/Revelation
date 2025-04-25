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

#if !defined INCLUDE_CLOUDS_LAYERS
#define INCLUDE_CLOUDS_LAYERS

#include "/lib/atmosphere/clouds/Common.glsl"

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

//================================================================================================//

float CloudMidDensity(in vec2 rayPos) {
	vec2 shift = cloudWindAs * CLOUD_WIND_SPEED;

	float localCoverage = GetSmoothNoise(rayPos * 2e-5 - shift * 0.25 + 32.0);

	/* Altostratus clouds */ if (localCoverage > 0.25) {
		// Curl noise to simulate wind, makes the positioning of the clouds more natural
		vec2 curl = texture(noisetex, rayPos * 1e-5).xy * 2e-4;

		vec2 position = (rayPos * 2e-4 - shift) * 4e-3 + curl;
		curl *= 0.5;

		float altostratus = texture(noisetex, position * 16.0).z, weight = 0.75;
		position += altostratus * 5e-3;

		// Altostratus FBM
		for (uint i = 0u; i < 5u; ++i, weight *= 0.55) {
			position = position * (2.75 - weight) + curl - shift * 2e-3;
			altostratus += weight * texture(noisetex, position).x;
		}

		localCoverage = saturate(localCoverage * 1.5 - 0.75);
		return sqr(saturate(altostratus + localCoverage * (1.0 + CLOUD_AS_COVERAGE) - 1.65));
	}
}

float CloudHighDensity(in vec2 rayPos) {
	vec2 shift = cloudWindCc * CLOUD_WIND_SPEED;

	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.03;
	curl += texture(noisetex, rayPos * 1e-5).xy * 0.015;

	float localCoverage = GetSmoothNoise(rayPos * 2e-5 + curl - shift * 0.25);
	float density = 0.0;

	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */ if (localCoverage > 0.4) {
		vec2 position = rayPos * 6e-5 - (shift + curl) * 0.5;

		float baseCoverage = texture(noisetex, position * 0.08).z * 0.75 + 0.25;
		baseCoverage *= saturate(1.0 - texture(noisetex, position * 0.003).y * 1.25);

		// The base shape of the cirrocumulus clouds using perlin-worley noise
		float cirrocumulus = 0.5 * texture(noisetex, position * vec2(0.4, 0.16)).z;
		cirrocumulus += texture(noisetex, position - shift).z - 0.5;

		cirrocumulus = remap(1.0 - saturate((baseCoverage + localCoverage) * 1.5 * (1.0 + CLOUD_CC_COVERAGE) - 1.65), 1.0, saturate(cirrocumulus));
		// if (cirrocumulus > EPS) {
			// position.x += (cirrocumulus - shift.x) * 0.125;

			// #if !defined PASS_SKY_VIEW
			// 	// Detail shape of the cirrocumulus clouds
			// 	cirrocumulus += 0.1 * texture(noisetex, position * 2.0).z - 0.08;
			// 	cirrocumulus += 0.06 * texture(noisetex, position * 4.0 + curl).z;
			// #endif

			density += pow4(saturate(cirrocumulus * 2.0));
		// }
	}
	#endif
	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */ if (localCoverage < 0.6) {
		shift = cloudWindCi * CLOUD_WIND_SPEED;
		vec2 position = rayPos * 5e-7 - shift * 2e-3 + curl * 3e-3 + 0.6;
		const vec2 angle = cossin(goldenAngle);
		const mat2 rot = mat2(angle, -angle.y, angle.x);
		vec2 scale = vec2(3.0);

		float weight = 0.55;
		float cirrus = texture(noisetex, position).x;

		// Cirrus FBM
		for (uint i = 0u; i < 5u; ++i, scale *= vec2(0.6, 1.1)) {
			position += (cirrus - shift + curl) * 2e-3;

			position = rot * position * scale;
			cirrus += texture(noisetex, position).x * weight;
			weight *= 0.45;
		}
		cirrus -= saturate(localCoverage * 2.0 - 0.8);
		cirrus = saturate(cirrus * (1.0 + CLOUD_CI_COVERAGE) - 1.6 - density);

		density += pow4(exp2(-curl.x * 8.0) * cirrus);
	}
	#endif

	return density;
}

#if 0
uniform sampler2D cirroClouds;

float CloudHighDensity(in vec2 rayPos) {
	vec2 shift = cloudWindCc * CLOUD_WIND_SPEED;

	float cloudType = saturate(texture(noisetex, (rayPos - cloudWindCc * 1e2) * 1e-7).x * 2.0 - 0.5);

	vec2 position = rayPos * 5e-6 - shift * 5e-2;
	float coverage = texture(noisetex, position).z * 0.85 + 0.15;
	coverage *= saturate(1.25 - texture(noisetex, position * 0.05).y * 1.75);

	vec3 cirroCloud = texture(cirroClouds, rayPos * 4e-5 - shift * 0.25).xyz;

	float density = remap(cloudType, 0.5, 1.0, remap(cloudType, 0.0, 0.5, cirroCloud.r, cirroCloud.g), cirroCloud.b); 
	density = pow(density, 2.0 - coverage * 1.75);
	density *= saturate(2.0 * cube(coverage));

	return sqr(saturate(4.0 * density));
}
#endif

//================================================================================================//

#if !defined PASS_VOLUMETRIC_FOG
	uniform sampler2D colortex11; // Vertical profile LUT
#endif

float GetVerticalProfile(in float heightFraction, in float cloudType) {
	return sqr(texture(colortex11, vec2(cloudType, heightFraction)).x * 1.65);
}

float CloudVolumeDensity(in vec3 rayPos, in bool detail) {
	vec3 cloudMap = texture(noisetex, (rayPos.xz - cloudWindCu.xz) * 1.25e-6).yzw;

	// Coveage profile
	float coverage = cloudMap.x + cloudMap.y - 1.0;
	coverage = saturate(mix(coverage * 2.0 * CLOUD_CU_COVERAGE, 1.0, wetness * 0.2));
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// Remap the height of the clouds to the range of [0, 1]
	float heightFraction = saturate((rayPos.y - CLOUD_CU_ALTITUDE) * rcp(CLOUD_CU_THICKNESS));

	// Vertical profile
	float verticalProfile = GetVerticalProfile(heightFraction, cloudMap.z);

	// See [Schneider, 2022]
	// Dimensional profile
	float dimensionalProfile = verticalProfile * coverage;
	if (dimensionalProfile < 1e-3) return 0.0;

	vec3 shift = CLOUD_WIND_SPEED * cloudWindCu;
	vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

	vec4 lowFreqNoises = texture(depthtex2, position * 0.25);
	float baseNoise = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));
	baseNoise = remap(baseNoise - 1.0, 1.0, lowFreqNoises.x);

	// coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	// float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	// cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
	if (detail) {
		vec2 curlNoise = texture(noisetex, position.xz * 0.05).xy;
		position.xy += curlNoise * 0.25 * oms(heightFraction);

		vec3 highFreqNoises = texture(colortex15, position * 4.0 - shift).xyz;
		detailNoise = dot(highFreqNoises, vec3(0.625, 0.25, 0.125));

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 10.0));

		// See [Schneider, 2023]
		// detailNoise = abs(detailNoise * 2.0 - 1.0);
	}
	#endif
	float noiseComposite = remap(detailNoise * oms(dimensionalProfile) * 0.7, 0.8, baseNoise);

	float cloudDensity = saturate(noiseComposite + dimensionalProfile - 1.0);

	float densityProfile = heightFraction * 2.5 + 0.5;
	return saturate(cloudDensity * densityProfile);
}

float CloudVolumeDensity(in vec3 rayPos, out float heightFraction) {
	vec3 cloudMap = texture(noisetex, (rayPos.xz - cloudWindCu.xz) * 1.25e-6).yzw;

	// Coveage profile
	float coverage = cloudMap.x + cloudMap.y - 1.0;
	coverage = saturate(mix(coverage * 2.0 * CLOUD_CU_COVERAGE, 1.0, wetness * 0.2));
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// Remap the height of the clouds to the range of [0, 1]
	heightFraction = saturate((rayPos.y - CLOUD_CU_ALTITUDE) * rcp(CLOUD_CU_THICKNESS));

	// Vertical profile
	float verticalProfile = GetVerticalProfile(heightFraction, cloudMap.z);

	// See [Schneider, 2022]
	// Dimensional profile
	float dimensionalProfile = verticalProfile * coverage;
	if (dimensionalProfile < 1e-3) return 0.0;

	vec3 shift = CLOUD_WIND_SPEED * cloudWindCu;
	vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

	vec4 lowFreqNoises = texture(depthtex2, position * 0.25);
	float baseNoise = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));
	baseNoise = remap(baseNoise - 1.0, 1.0, lowFreqNoises.x);

	// coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	// float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	// cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
		vec2 curlNoise = texture(noisetex, position.xz * 0.05).xy;
		position.xy += curlNoise * 0.25 * oms(heightFraction);

		vec3 highFreqNoises = texture(colortex15, position * 4.0 - shift).xyz;
		detailNoise = dot(highFreqNoises, vec3(0.625, 0.25, 0.125));

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 10.0));

		// See [Schneider, 2023]
		// detailNoise = abs(detailNoise * 2.0 - 1.0);
	#endif
	float noiseComposite = remap(detailNoise * oms(dimensionalProfile) * 0.7, 0.8, baseNoise);

	float cloudDensity = saturate(noiseComposite + dimensionalProfile - 1.0);

	float densityProfile = heightFraction * 2.5 + 0.5;
	return saturate(cloudDensity * densityProfile);
}

#endif