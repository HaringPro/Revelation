#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

vec3 FetchSmoothNoise(in vec2 coord) {
	coord *= 256.0;

    vec2 whole = floor(coord);
    vec2 part = curve(coord - whole);

	coord = (whole + 1.0) * rcp(256.0);
	vec4 sx = textureGather(noisetex, coord, 0);
	vec4 sy = textureGather(noisetex, coord, 1);
	vec4 sz = textureGather(noisetex, coord, 2);

    vec3 s0 = mix(vec3(sx.w, sy.w, sz.w), vec3(sx.z, sy.z, sz.z), part.x);
    vec3 s1 = mix(vec3(sx.x, sy.x, sz.x), vec3(sx.y, sy.y, sz.y), part.x);
    return mix(s0, s1, part.y);
}

// Based on https://www.shadertoy.com/view/MdXyzX
// afl_ext 2017-2024
// MIT License
vec2 wavedx(vec2 position, vec2 direction, float frequency, float time) {
	float c = approxSqrt(9.8 * frequency);

	#if WATER_WAVE_STYLE == 0
		float x = time * c + dot(direction, position) * frequency;
	#else
		float x = time * c - dot(direction, position) * frequency;
	#endif

	float wave = exp2(sin(x));
	float dx = wave * cos(x);

	return vec2(wave, dx);
}

float CalculateWaterHeight(in vec2 position) {
	vec3 noise = FetchSmoothNoise((position + frameTimeCounter) * 2e-3);
	vec2 dir = vec2(0.0);

	float frequency = 1.0;
	float weight = 1.0;
	float sum = 0.0;
	float sumWeight = 0.0;

	float waveTime = WATER_WAVE_SPEED * frameTimeCounter;
	position += noise.z * 8.0;

	for (uint i = 0u; i < 14u; ++i) {
		dir = sincos(Halton2(i) * hPI);
		frequency *= 1.22;
		weight *= 0.8;

		vec2 res = wavedx(position + dir * noise.xy * (8.0 * weight), dir, frequency, waveTime);
		position -= dir * res.y * weight * 0.2;

		sum += res.x * weight;
		sumWeight += weight;
	}

	#if !defined PASS_SHADOW
		sum *= saturate(noise.z * 2.0 - 1.0) * 3.0 + 0.75;
	#endif

	return sum / sumWeight * (0.125 * WATER_WAVE_HEIGHT);
}

//================================================================================================//

vec3 CalculateWaterNormal(in vec2 position) {
	const float delta = 0.1;

	float height0 = CalculateWaterHeight(position);
	float height1 = CalculateWaterHeight(position + vec2(delta, 0.0));
	float height2 = CalculateWaterHeight(position + vec2(0.0, delta));

	vec2 waveNormal = vec2(height0 - height1, height0 - height2);
	waveNormal *= rcp(1.0 + dot(fwidth(position), vec2(0.15)));
	return normalize(vec3(waveNormal, delta));
}

vec3 CalculateWaterNormal(in vec3 rayPos, in vec3 rayDir) {
	const uint steps = 8u;

	vec3 rayStep = vec3(rayDir.xy / rayDir.z, 1.0) * inversesqrt(steps);

	float height = CalculateWaterHeight(rayPos.xz);
	vec3 offset = vec3(0.0, 0.0, 1.0) + height * rayStep;

	for (uint i = 0u; i < steps && height < offset.z; ++i) {
		height = CalculateWaterHeight(rayPos.xz + offset.xy);
		offset += (height - offset.z) * rayStep;
	}

	return CalculateWaterNormal(rayPos.xz + offset.xy);
}

#endif