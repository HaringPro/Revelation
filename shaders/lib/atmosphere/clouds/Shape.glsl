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

	rayPos += 40.0;
	float localCoverage = GetSmoothNoise(rayPos * 4e-5 - shift * 0.3);

	/* Stratocumulus clouds */ if (localCoverage > 0.2) {
		// Curl noise to simulate wind, makes the positioning of the clouds more natural
		vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.05;

		vec2 position = (rayPos * 2e-4 - shift + curl) * 2e-3;

		float altostratus = texture(noisetex, position * 16.0).z * 0.84, weight = 0.5;

		// Stratocumulus FBM
		for (uint i = 0u; i < 5u; ++i, weight *= 0.6) {
			position = position * (3.0 - weight + curl) + altostratus * 0.02 * weight;
			altostratus += weight * texture(noisetex, position).x;
		}

		localCoverage = saturate(localCoverage * 1.6 - 0.8) * 0.5 + 0.5;
		return sqr(saturate(altostratus * (1.0 + CLOUD_AS_COVERAGE) * localCoverage - 1.0));
	}
}

float CloudHighDensity(in vec2 rayPos) {
	vec2 shift = cloudWindCc * CLOUD_WIND_SPEED;

	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.03;
	curl += texture(noisetex, rayPos * 1e-5).xy * 0.015;

	float localCoverage = GetSmoothNoise(rayPos * 2e-5 + curl - shift * 0.3);
	float density = 0.0;

	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */ if (localCoverage > 0.5) {
		vec2 position = rayPos * 7e-5 - (shift + curl) * 0.6 + 0.15;

		float baseCoverage = curve(texture(noisetex, position * 0.08).z * 0.65 + 0.1);
		baseCoverage *= max0(1.04 - texture(noisetex, position * 0.003).y * 1.36);

		// The base shape of the cirrocumulus clouds using perlin-worley noise
		float cirrocumulus = 0.5 * texture(noisetex, position * vec2(0.4, 0.16)).z;
		cirrocumulus += texture(noisetex, (position - shift) * 0.9).z - 0.3;
		cirrocumulus = saturate(cirrocumulus - density - 0.014);

		cirrocumulus *= clamp(baseCoverage + saturate(localCoverage * (1.0 + CLOUD_CC_COVERAGE) - 0.8) - 0.45, 0.0, 0.2);
		if (cirrocumulus > 1e-6) {
			position.x += (cirrocumulus - shift.x) * 0.2;

			#if !defined PASS_SKY_VIEW
				// Detail shape of the cirrocumulus clouds
				cirrocumulus += 0.016 * texture(noisetex, position * 3.0).z;
				cirrocumulus += 0.01 * texture(noisetex, position * 5.0 + curl).z - 0.026;
			#endif

			density += cube(saturate(cirrocumulus * 2.4)) * 3.2;
		}
	}
	#endif
	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */ if (density < 0.1) {
		shift = cloudWindCi * CLOUD_WIND_SPEED;
		vec2 position = rayPos * 5e-7 - shift * 2e-3 + curl * 3e-3 + 0.6;
		const vec2 angle = cossin(goldenAngle);
		const mat2 rot = mat2(angle, -angle.y, angle.x);
		vec2 scale = vec2(3.0);

		float weight = 0.6;
		float cirrus = texture(noisetex, position).x;

		// Cirrus FBM
		for (uint i = 1u; i < 6u; ++i, scale *= vec2(0.6, 1.1)) {
			position += (cirrus - shift + curl) * 2e-3;

			position = rot * position * scale;
			cirrus += texture(noisetex, position).x * exp2(-float(i) * 1.3);
		}
		cirrus -= saturate(localCoverage * 2.0 - 0.8);
		cirrus = saturate(cirrus * (1.0 + CLOUD_CI_COVERAGE) - 1.4 - density);

		density += cube(0.4 * exp2(-curl.x * 8.0) * cirrus);
	}
	#endif

	return saturate(density);
}

//================================================================================================//

float ConstructVerticalProfile(in float heightFraction, in float cloudType) {
	float base = saturate(1.0 - heightFraction * (2.0 - cloudType));
	float top = saturate(6.0 - heightFraction * 6.0);
	float bottom = saturate(heightFraction * 8.0);
	return saturate(base + top * bottom - 1.0);
}

float CloudVolumeDensity(in vec3 rayPos, in bool detail) {
	vec3 cloudMap = texture(noisetex, rayPos.xz * 1.25e-6 - cloudWindCu.xz * 2e-5).yzw;

	// Coveage profile
	float coverage = cloudMap.x + cloudMap.y - 1.0;
	coverage = saturate(mix(coverage * 2.0 * CLOUD_CU_COVERAGE, 1.0, wetness * 0.2));
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// See [Schneider, 2017]
	float cloudType = saturate(cloudMap.z * 1.25 + 0.125);

	// Remap the height of the clouds to the range of [0, 1]
	float heightFraction = saturate((rayPos.y - CLOUD_CU_ALTITUDE) * rcp(CLOUD_CU_THICKNESS));

	vec3 shift = CLOUD_WIND_SPEED * cloudWindCu;
	vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

	vec4 lowFreqNoises = texture(depthtex2, position * 0.25);
	float baseNoise = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));
	baseNoise = remap(baseNoise - 1.0, 1.0, lowFreqNoises.x);

	// // Vertical profile
	// float verticalProfile = ConstructVerticalProfile(heightFraction, cloudMap.z);

	// // See [Schneider, 2022]
	// // Dimensional profile
	// float dimensionalProfile = verticalProfile * coverage;
	// if (dimensionalProfile < 1e-3) return 0.0;

	// float cloudDensity = 1.5 * saturate(baseNoise + dimensionalProfile - 1.0);
	coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
	if (cloudDensity > 0.025 && detail) {
		vec2 curlNoise = texture(noisetex, position.xz * 0.05).xy;
		position.xy += curlNoise * 0.25 * oms(heightFraction);

		vec3 highFreqNoises = texture(colortex15, position * 4.0 - shift).xyz;
		detailNoise = dot(highFreqNoises, vec3(0.625, 0.25, 0.125));

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 10.0));
	}
	#endif
	cloudDensity = remap(detailNoise * 0.25, 0.375, cloudDensity);

	float densityProfile = saturate(heightFraction * 1.5 + 0.25);
	return cloudDensity * densityProfile;
}

float CloudVolumeDensity(in vec3 rayPos, out float heightFraction) {
	vec3 cloudMap = texture(noisetex, rayPos.xz * 1.25e-6 - cloudWindCu.xz * 2e-5).yzw;

	// Coveage profile
	float coverage = cloudMap.x + cloudMap.y - 1.0;
	coverage = saturate(mix(coverage * 2.0 * CLOUD_CU_COVERAGE, 1.0, wetness * 0.2));
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// See [Schneider, 2017]
	float cloudType = saturate(cloudMap.z * 1.25 + 0.125);

	// Remap the height of the clouds to the range of [0, 1]
	heightFraction = saturate((rayPos.y - CLOUD_CU_ALTITUDE) * rcp(CLOUD_CU_THICKNESS));

	vec3 shift = CLOUD_WIND_SPEED * cloudWindCu;
	vec3 position = (rayPos + cumulusTopOffset * heightFraction) * 5e-4 - shift;

	vec4 lowFreqNoises = texture(depthtex2, position * 0.25);
	float baseNoise = dot(lowFreqNoises.yzw, vec3(0.625, 0.25, 0.125));
	baseNoise = remap(baseNoise - 1.0, 1.0, lowFreqNoises.x);

	// // Vertical profile
	// float verticalProfile = ConstructVerticalProfile(heightFraction, cloudMap.z);

	// // See [Schneider, 2022]
	// // Dimensional profile
	// float dimensionalProfile = verticalProfile * coverage;
	// if (dimensionalProfile < 1e-3) return 0.0;

	// float cloudDensity = 1.5 * saturate(baseNoise + dimensionalProfile - 1.0);
	coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
	if (cloudDensity > 0.025) {
		vec2 curlNoise = texture(noisetex, position.xz * 0.05).xy;
		position.xy += curlNoise * 0.25 * oms(heightFraction);

		vec3 highFreqNoises = texture(colortex15, position * 4.0 - shift).xyz;
		detailNoise = dot(highFreqNoises, vec3(0.625, 0.25, 0.125));

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 10.0));
	}
	#endif
	cloudDensity = remap(detailNoise * 0.25, 0.375, cloudDensity);

	float densityProfile = saturate(heightFraction * 1.5 + 0.25);
	return cloudDensity * densityProfile;
}

#endif