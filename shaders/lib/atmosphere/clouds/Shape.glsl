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

float Pseudo3DNoiseSmooth(in vec3 position) {
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
	// Wind field
	const float windAngle = radians(10.0);
	const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_AS_WIND_SPEED;
	vec2 windOffset = windVelocity * worldTimeCounter;

	rayPos -= windOffset;

	float localCoverage = GetSmoothNoise(rayPos * 3e-5 + 32.0);
	localCoverage += texture(noisetex, rayPos * 5e-6).z;

	/* Altostratus clouds */ if (localCoverage > 0.25) {
		// Curl noise to simulate wind, makes the positioning of the clouds more natural
		vec2 curl = texture(noisetex, rayPos * 1e-5).xy * 2e-4;

		vec2 position = (rayPos - windOffset * 0.5) * 1e-6 + curl;
		curl *= 0.5;

		float altostratus = texture(noisetex, position * 16.0).z, weight = 0.75;
		position += altostratus * 5e-3;

		// Altostratus FBM
		for (uint i = 0u; i < 5u; ++i, weight *= 0.55) {
			position = position * (2.75 - weight) + curl - windOffset * 1e-6;
			altostratus += weight * texture(noisetex, position).x;
		}

		localCoverage = saturate(localCoverage * 1.15 - 1.0);
		return sqr(saturate(altostratus * localCoverage * (1.0 + CLOUD_AS_COVERAGE) - 0.5));
	}
}

float CloudHighDensity(in vec2 rayPos) {
	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.03;
	curl += texture(noisetex, rayPos * 1e-5).xy * 0.015;

	float localCoverage = GetSmoothNoise((rayPos - worldTimeCounter * 20.0) * 2e-5 + curl);
	float density = 0.0;

	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */ if (localCoverage > 0.4) {
		// Wind field
		const float windAngle = radians(20.0);
		const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_CC_WIND_SPEED;
		vec2 windOffset = windVelocity * worldTimeCounter;

		vec2 position = (rayPos - windOffset) * 1e-4 - curl * 0.75;
		windOffset *= 5e-5;

		float baseCoverage = texture(noisetex, position * 0.1).z;
		baseCoverage *= saturate(1.0 - texture(noisetex, position * 0.005).y);
		position -= windOffset;

		float cirrocumulus = 0.5 * texture(noisetex, position * vec2(0.5, 0.2)).z;
		cirrocumulus += texture(noisetex, position - windOffset + cirrocumulus * 0.125).z - 0.5;
		cirrocumulus = sqr(saturate(1.5 * cirrocumulus));

		float coverage = saturate((baseCoverage + localCoverage) * 2.0 * (1.0 + CLOUD_CC_COVERAGE) - 2.75);

		cirrocumulus = mix(cirrocumulus * cirrocumulus, cirrocumulus, coverage);
		cirrocumulus *= saturate(2.0 * cube(coverage));

		density += sqr(saturate(1.5 * cirrocumulus));
	}
	#endif
	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */ if (localCoverage < 0.6) {
		// Wind field
		const float windAngle = radians(30.0);
		const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_CI_WIND_SPEED;
		vec2 windOffset = windVelocity * worldTimeCounter;

		vec2 position = (rayPos - windOffset) * 4e-7 + curl * 5e-3;
		windOffset *= 2e-7;

		const vec2 angle = cossin(goldenAngle);
		const mat2 rot = mat2(angle, -angle.y, angle.x);
		vec2 scale = vec2(2.5, 2.0);

		float weight = 0.55;
		float cirrus = 1.0 - texture(noisetex, position * vec2(0.75, 1.25)).x;

		// Cirrus FBM
		for (uint i = 0u; i < 5u; ++i, scale *= vec2(0.75, 1.25)) {
			position += (cirrus + curl) * 3e-3 - windOffset;

			position = rot * position * scale;
			cirrus += oms(texture(noisetex, position).x) * weight;
			weight *= 0.55;
		}
		cirrus -= saturate(localCoverage * 2.0 - 0.9);
		cirrus = saturate(cirrus * (1.0 + CLOUD_CI_COVERAGE) - 1.75);

		density += exp2(-curl.x * 8.0) * pow4(cirrus);
	}
	#endif

	return density;
}

//================================================================================================//

#if 1
uniform sampler2D colortex11; // Vertical profile LUT

float GetVerticalProfile(in float heightFraction, in float cloudType) {
	return texture(colortex11, vec2(cloudType, heightFraction)).x;
}
#else

// Adapted from https://github.com/iamlivehaha/Project-VolumetricCloudRendering
// Get the blended density gradient for 3 different cloud types
// relativeHeight is normalized distance from inner to outer atmosphere shell
// cloudType is read from cloud placement blue channel
float GetVerticalProfile(in float relativeHeight, in float cloudType) {
    float altocumulus = remap(0.01, 0.3, relativeHeight) * remap(0.95, 0.6, relativeHeight);
    float cumulus = saturate(relativeHeight * 4.0) * remap(0.65, 0.3, relativeHeight);
    float stratus = saturate(relativeHeight * 10.0) * remap(0.3, 0.2, relativeHeight);

    float stratocumulus = mix(stratus, cumulus, saturate(cloudType * 2.0));
    float cumulonimbus = mix(cumulus, altocumulus, saturate(cloudType * 2.0 - 1.0));
    return mix(stratocumulus, cumulonimbus, cloudType);
}
#endif

float CloudVolumeDensity(in vec3 rayPos, in bool detail) {
	// Remap the height of the clouds to the range of [0, 1]
	float rayRadius = sdot(rayPos); rayRadius *= inversesqrt(rayRadius);
	float heightFraction = saturate((rayRadius - cumulusBottomRadius) * rcp(CLOUD_CU_THICKNESS));

	// Wind field
	const float windAngle = radians(45.0);
	const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
	const vec3 windVelocity = windDir * CLOUD_CU_WIND_SPEED;
	vec3 windOffset = windVelocity * worldTimeCounter;

	rayPos -= windOffset;
	rayPos -= windDir * cumulusTopOffset * heightFraction;

	// Sample cloud map
	vec2 cloudMap = texture(depthtex1, rayPos.xz * rcp(cloudMapCovDist)).xy;

	// Coveage profile
	float coverage = cloudMap.x * (2.0 * CLOUD_CU_COVERAGE);
	coverage = saturate(coverage + wetness * 0.5);
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// Vertical profile
	float verticalProfile = GetVerticalProfile(heightFraction, cloudMap.y);

	// See [Schneider, 2022]
	// Dimensional profile
	float dimensionalProfile = saturate(verticalProfile * coverage);
	if (dimensionalProfile < 1e-3) return 0.0;

	vec3 position = (rayPos - windOffset * 0.5) * 2.5e-4;

	// Perlin-worley + fBm worley noise for base shape
	float baseNoise = texture(baseNoiseTex, position).x;

	// coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	// float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	// cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
	if (detail) {
		vec2 curlNoise = texture(noisetex, position.xz * 0.25).xy;
		position.xz += curlNoise * 0.25 * oms(heightFraction);

		// fBm worley noise for detail shape
		detailNoise = texture(detailNoiseTex, position * 8.0 - windOffset * 1e-3).x;

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 8.0));

		// See [Schneider, 2023]
		// detailNoise = abs(detailNoise * 2.0 - 1.0);
	}
	#endif
	float noiseComposite = remap(detailNoise * 0.25, 1.0, baseNoise);

	float cloudDensity = saturate(noiseComposite + dimensionalProfile - 1.0);

	float densityProfile = saturate(heightFraction * 2.0 + 0.125);
	return pow(cloudDensity, 0.75 - heightFraction * 0.25) * densityProfile;
}

float CloudVolumeDensity(in vec3 rayPos, out float heightFraction, out float dimensionalProfile) {
	// Remap the height of the clouds to the range of [0, 1]
	float rayRadius = sdot(rayPos); rayRadius *= inversesqrt(rayRadius);
	heightFraction = saturate((rayRadius - cumulusBottomRadius) * rcp(CLOUD_CU_THICKNESS));

	// Wind field
	const float windAngle = radians(45.0);
	const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
	const vec3 windVelocity = windDir * CLOUD_CU_WIND_SPEED;
	vec3 windOffset = windVelocity * worldTimeCounter;

	rayPos -= windOffset;
	rayPos -= windDir * cumulusTopOffset * heightFraction;

	// Sample cloud map
	vec2 cloudMap = texture(depthtex1, rayPos.xz * rcp(cloudMapCovDist)).xy;

	// Coveage profile
	float coverage = cloudMap.x * (2.0 * CLOUD_CU_COVERAGE);
	coverage = saturate(coverage + wetness * 0.5);
	// coverage = pow(coverage, remap(heightFraction, 0.7, 0.8, 1.0, 1.0 - 0.5 * anvilBias));
	if (coverage < 1e-2) return 0.0;

	// Vertical profile
	float verticalProfile = GetVerticalProfile(heightFraction, cloudMap.y);

	// See [Schneider, 2022]
	// Dimensional profile
	dimensionalProfile = saturate(verticalProfile * coverage);
	if (dimensionalProfile < 1e-3) return 0.0;

	vec3 position = (rayPos - windOffset * 0.5) * 2.5e-4;

	// Perlin-worley + fBm worley noise for base shape
	float baseNoise = texture(baseNoiseTex, position).x;

	// coverage += 0.3 - remap(0.25, 1.0, heightFraction / cloudType) * 0.25;
	// float cloudDensity = 2.0 * saturate(baseNoise + coverage - 1.0);
	// cloudDensity *= saturate(heightFraction * 6.0);

	// Detail shape
	float detailNoise = 0.5;
	#if !defined PASS_SKY_VIEW
		vec2 curlNoise = texture(noisetex, position.xz * 0.25).xy;
		position.xz += curlNoise * 0.25 * oms(heightFraction);

		// fBm worley noise for detail shape
		detailNoise = texture(detailNoiseTex, position * 8.0 - windOffset * 1e-3).x;

		// Transition from wispy shapes to billowy shapes over height
		detailNoise = mix(detailNoise, 1.0 - detailNoise, saturate(heightFraction * 8.0));

		// See [Schneider, 2023]
		// detailNoise = abs(detailNoise * 2.0 - 1.0);
	#endif
	float noiseComposite = remap(detailNoise * 0.25, 1.0, baseNoise);

	float cloudDensity = saturate(noiseComposite + dimensionalProfile - 1.0);

	float densityProfile = saturate(heightFraction * 2.0 + 0.125);
	return pow(cloudDensity, 0.75 - heightFraction * 0.25) * densityProfile;
}

#endif