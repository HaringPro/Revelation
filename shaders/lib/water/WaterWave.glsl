#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

float FetchNoise(in vec2 coord, in float t) {
	coord.y = coord.y * 2.0 + t;
	return sqr(1.0 - texture(noisetex, coord).z);
}

float FetchNoiseSmooth(in vec2 coord, in float t) {
	coord.y = coord.y * 2.0 + t;
	return sqr(1.0 - textureBicubic(noisetex, coord).z);
}

float CalculateWaterHeight(in vec2 position) {
	vec2 pos = 0.01 * position;
	float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
	float waves = FetchNoise(pos, waveTime);

	pos = goldenRotate * (1.75 * pos) + waves * 0.05;
	waveTime *= 1.25;
	waves += FetchNoise(pos, waveTime) * 0.75;

	pos = goldenRotate * (1.75 * pos) + waves * 0.05;
	waveTime *= 1.25;
	waves += FetchNoise(pos, waveTime) * 0.15;

	// pos = goldenRotate * (1.5 * pos);
	// waves += FetchNoise(pos, waveTime) * 0.1;

	#if !defined PASS_SHADOW
		float localHeight = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
		waves *= saturate(localHeight * 2.0 - 0.75) + 0.25;
	#endif

	return WATER_WAVE_HEIGHT * 0.5 * waves;
}

float CalculateWaterHeightFull(in vec2 position) {
	vec2 pos = 0.01 * position;
	float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
	float waves = FetchNoiseSmooth(pos, waveTime);

	pos = goldenRotate * (1.75 * pos) + waves * 0.05;
	waveTime *= 1.25;
	waves += FetchNoiseSmooth(pos, waveTime) * 0.75;

	pos = goldenRotate * (1.75 * pos) + waves * 0.05;
	waveTime *= 1.25;
	waves += FetchNoiseSmooth(pos, waveTime) * 0.15;

	pos = goldenRotate * (1.5 * pos);
	waves += FetchNoise(pos, waveTime) * 0.1;

	#if !defined PASS_SHADOW
		float localHeight = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
		waves *= saturate(localHeight * 2.0 - 0.75) + 0.25;
	#endif

	return WATER_WAVE_HEIGHT * 0.5 * waves;
}

//================================================================================================//

vec3 CalculateWaterNormal(in vec2 position) {
	const float delta = 0.1;

	float height0 = CalculateWaterHeightFull(position);
	float height1 = CalculateWaterHeightFull(position + vec2(delta, 0.0));
	float height2 = CalculateWaterHeightFull(position + vec2(0.0, delta));

	vec2 waveNormal = vec2(height0 - height1, height0 - height2);
	return normalize(vec3(waveNormal, delta * (1.0 + dot(fwidth(position), vec2(0.2)))));
}

vec3 CalculateWaterNormal(in vec3 rayPos, in vec3 rayDir) {
	const uint steps = 12u;

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