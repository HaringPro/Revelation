#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

float FetchNoise(vec2 coord, float t) {
	coord.y = coord.y * 2.0 + t;
	return sqr(1.0 - texture(noisetex, coord).z);
}

float FetchNoiseSmooth(vec2 coord, float t) {
	coord.y = coord.y * 2.0 + t;
	return sqr(1.0 - textureBicubic(noisetex, coord).z);
}

float CalculateWaterHeight(vec2 position) {
	#if RENDER_MODE == 1
		float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
	#else
		float waveTime = 0.0;
	#endif
	vec2 pos = 0.0075 * position;

	float waveHeight = WATER_WAVE_HEIGHT * 0.4;
	#if !defined PASS_SHADOW
		float lfNoise = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
		waveHeight *= saturate(lfNoise * 2.0 - 0.75) + 0.25;
		pos += lfNoise * 0.05;
	#endif

	float waves = FetchNoise(pos, waveTime);

	pos = goldenRotate * (1.75 * pos) + waves * 0.03;
	waveTime *= 1.25;
	waves += FetchNoise(pos, waveTime) * 0.75;

	pos = goldenRotate * (1.75 * pos) + waves * 0.03;
	waveTime *= 1.25;
	waves += FetchNoise(pos, waveTime) * 0.15;

	pos = goldenRotate * (1.5 * pos);
	waves += FetchNoise(pos, waveTime) * 0.1;

	return waveHeight * waves;
}

float CalculateWaterHeightFull(vec2 position) {
	#if RENDER_MODE == 1
		float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
	#else
		float waveTime = 0.0;
	#endif
	vec2 pos = 0.0075 * position;

	float waveHeight = WATER_WAVE_HEIGHT * 0.4;
	#if !defined PASS_SHADOW
		float lfNoise = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
		waveHeight *= saturate(lfNoise * 2.0 - 0.75) + 0.25;
		pos += lfNoise * 0.05;
	#endif

	float waves = FetchNoiseSmooth(pos, waveTime);

	pos = goldenRotate * (1.75 * pos) + waves * 0.03;
	waveTime *= 1.25;
	waves += FetchNoiseSmooth(pos, waveTime) * 0.75;

	pos = goldenRotate * (1.75 * pos) + waves * 0.03;
	waveTime *= 1.25;
	waves += FetchNoiseSmooth(pos, waveTime) * 0.15;

	pos = goldenRotate * (1.5 * pos);
	waves += FetchNoise(pos, waveTime) * 0.1;

	pos = goldenRotate * (1.25 * pos);
	waves += FetchNoise(pos, waveTime) * 0.1;

	return waveHeight * waves;
}

//================================================================================================//

vec3 CalculateWaterNormal(vec2 position) {
	const float delta = 0.05;

	float height0 = CalculateWaterHeightFull(position);
	float height1 = CalculateWaterHeightFull(position + vec2(delta, 0.0));
	float height2 = CalculateWaterHeightFull(position + vec2(0.0, delta));

	vec2 waveNormal = vec2(height0 - height1, height0 - height2);
	return normalize(vec3(waveNormal, delta * (1.0 + dot(fwidth(position), vec2(0.2)))));
}

vec3 CalculateWaterNormal(vec3 rayPos, vec3 rayDir) {
	const uint steps = WATER_PARALLAX_SAMPLES;

	vec3 rayStep = vec3(rayDir.xy / rayDir.z, 1.0) * inversesqrt(steps);

	float height = CalculateWaterHeight(rayPos.xz);
	vec3 offset = vec3(0.0, 0.0, 1.0) + height * rayStep;

	for (uint i = 0u; i < steps && height < offset.z; ++i) {
		height = CalculateWaterHeight(rayPos.xz + offset.xy);
		offset += (height - offset.z) * rayStep;
	}

	return CalculateWaterNormal(rayPos.xz + offset.xy);
}

#endif // INCLUDE_WATER_WATERWAVE
