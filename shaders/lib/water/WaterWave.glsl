#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

float FetchNoise(in vec2 coord, in float t) {
	coord.y *= 0.5;
	return sqr(1.0 - texture(noisetex, coord + t).z);
}

// fBm water wave
float CalculateWaterHeight(in vec2 position, in bool detail) {
	const vec2 angle = 2.0 * cossin(goldenAngle);
	const mat2 rot = mat2(angle, -angle.y, angle.x);

	float waveTime = 0.01 * WATER_WAVE_SPEED * worldTimeCounter;
	vec2 pos = 0.015 * position + waveTime * 0.5;
	#if defined PASS_DEFERRED_LIGHTING || defined PASS_VOLUMETRIC_FOG
		float waves = 0.0;
	#else
		float waves = FetchNoise(pos, waveTime);
	#endif

	pos = rot * pos + waves * 0.05;
	waves += FetchNoise(pos, waveTime) * 0.75;

	if (detail) {
		pos = pos * rot + waves * 0.05;
		waves += FetchNoise(pos, waveTime) * 0.15;

		pos = rot * pos;
		waves += FetchNoise(pos, waveTime) * 0.05;

		pos = pos * rot;
		waves += FetchNoise(pos, waveTime) * 0.03;
	}

	#if !(defined PASS_DEFERRED_LIGHTING || defined PASS_VOLUMETRIC_FOG)
		float localHeight = texture(noisetex, position * 2e-3 + waveTime * 0.125).z;
		waves *= max(localHeight * 5.0 - 1.8, 0.6);
	#endif

	return waves;
}

//================================================================================================//

vec3 CalculateWaterNormal(in vec2 position) {
	const float delta = 0.05;

	float heightCenter = CalculateWaterHeight(position, true);
	float heightLeft   = CalculateWaterHeight(position + vec2(delta, 0.0), true);
	float heightUp     = CalculateWaterHeight(position + vec2(0.0, delta), true);

	vec2 waveNormal    = vec2(heightCenter - heightLeft, heightCenter - heightUp);
	return normalize(vec3(waveNormal * WATER_WAVE_HEIGHT, delta));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir, in float dither) {
	const uint steps = 32u;
	const float rSteps = rcp(float(steps));

	vec3 rayStep = vec3(tangentViewDir.xy * WATER_WAVE_HEIGHT, rSteps);
	rayStep.xy *= rSteps / tangentViewDir.z;

    vec3 samplePos = vec3(position, 1.0) - rayStep * dither;
	float sampleHeight = CalculateWaterHeight(samplePos.xy, false);

	while (sampleHeight < samplePos.z) {
        samplePos -= rayStep;
		sampleHeight = CalculateWaterHeight(samplePos.xy, false);
	}

	return CalculateWaterNormal(samplePos.xy);
}

#endif