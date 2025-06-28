#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

float FetchNoise(in vec2 coord) {
	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part + 0.5;

	return textureLod(noisetex, coord * noiseTexturePixelSize, 0.0).x;
}

#if defined PASS_DEFERRED_LIGHTING && defined WATER_CAUSTICS_SIMPLE
float CalculateWaterHeight(in vec2 position) {
	float waveTime = frameTimeCounter * WATER_WAVE_SPEED;

	vec2 pos = vec2(1.4, 0.92) * position + vec2(1.1, -0.8) * waveTime;
	// Manually rotate
	pos.y -= pos.x * 1.2;
	float waves = FetchNoise(pos) * 0.24 - 0.24;

	pos = vec2(3.5, 2.2) * position + vec2(2.2, 0.7) * waveTime;
	// Manually rotate
	pos.y += pos.x * 0.6;
	waves += FetchNoise(pos) * 0.09 - 0.09;

	pos = vec2(7.0, 3.9) * position + vec2(1.8, 0.8) * waveTime;
	// Manually rotate
	pos.y -= pos.x;
	waves += FetchNoise(pos) * 0.03 - 0.03;

	return waves * 0.5;
}
#else
float CalculateWaterHeight(in vec2 position) {
	float waveTime = frameTimeCounter * WATER_WAVE_SPEED;

	vec2 pos = vec2(0.4, 0.31) * position + vec2(0.8, 0.12) * waveTime;
	// Manually rotate
	pos += pos.yx * vec2(0.2, 1.3);
	float waves = FetchNoise(pos) - 1.0;
	waves = waves * waves - 1.0;

	pos = vec2(0.64, 0.42) * position + vec2(0.16, 0.24) * waveTime;
	// Manually rotate
	pos += pos.yx * vec2(0.1, 0.4) + waves;
	waves += curve(FetchNoise(pos)) - 1.0;

	pos = vec2(1.4, 0.92) * position + vec2(1.1, -0.8) * waveTime;
	// Manually rotate
	pos.y -= pos.x * 1.2;
	waves += FetchNoise(pos) * 0.24 - 0.24;

	pos = vec2(3.5, 2.2) * position + vec2(2.2, 0.7) * waveTime;
	// Manually rotate
	pos.y += pos.x * 0.6;
	waves += FetchNoise(pos) * 0.09 - 0.09;

	pos = vec2(7.0, 3.9) * position + vec2(1.8, 0.8) * waveTime;
	// Manually rotate
	pos.y -= pos.x;
	waves += FetchNoise(pos) * 0.03 - 0.03;

	return waves * 0.25;
}
#endif


// https://www.shadertoy.com/view/MdXyzX
// Calculates wave value and its derivative, 
// for the wave direction, position in space, wave frequency and time
vec2 wavedx(vec2 position, vec2 direction, float frequency, float timeshift) {
	float x = dot(direction, position) * frequency - timeshift;
	float wave = fastExp(sin(x) - 1.0);
	float dx = wave * cos(x);
	return vec2(wave, -dx);
}

// Calculates waves by summing octaves of various waves with various parameters
float getwaves(vec2 position) {
	float frequency = 1.0; // frequency of the wave, this will change every iteration
	float timeMultiplier = 1.5; // time multiplier for the wave, this will change every iteration
	float weight = 1.0; // weight in final sum for the wave, this will change every iteration
	float sumOfValues = 0.0; // will store final sum of values
	float sumOfWeights = 0.0; // will store final sum of weights

	const vec2 angle = cossin(goldenAngle);
	const mat2 rot = mat2(angle, -angle.y, angle.x);

	vec2 dir = sincos(TAU);

	vec2 noise = 4.0 * texture(noisetex, (position - frameTimeCounter) * 0.001).xy;
	position += noise;

	for (uint i = 0u; i < 12u; ++i) {
		// generate some wave direction that looks kind of random
		dir *= rot;
		vec2 res = wavedx(position, dir, frequency, frameTimeCounter * timeMultiplier);

		// shift position around according to wave drag and derivative of the wave
		position += dir * (res.y * weight * 0.5 + noise);

		// add the results to sums
		sumOfValues += res.x * weight;
		sumOfWeights += weight;

		// modify next octave
		weight *= 0.8;
		frequency *= 1.25;
		timeMultiplier *= 1.1;
	}

	// calculate and return
	return (sumOfValues / sumOfWeights - 1.0) * FetchNoise(position * 0.25) * 2.0;
}

//================================================================================================//

vec3 CalculateWaterNormal(in vec2 position) {
	const float delta = 0.1;

	float heightCenter = CalculateWaterHeight(position);
	float heightLeft   = CalculateWaterHeight(position + vec2(delta, 0.0));
	float heightUp     = CalculateWaterHeight(position + vec2(0.0, delta));

	vec2 waveNormal    = vec2(heightCenter - heightLeft, heightCenter - heightUp);
	return normalize(vec3(waveNormal * WATER_WAVE_HEIGHT, delta));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	const uint steps = 16u;
	const float rSteps = rcp(float(steps));

	vec3 rayStep = vec3(tangentViewDir.xy * WATER_WAVE_HEIGHT, -rSteps);
	rayStep.xy *= rSteps / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 0.0) + rayStep;
	float sampleHeight = CalculateWaterHeight(samplePos.xy);

	while (sampleHeight < samplePos.z) {
        samplePos += rayStep;
		sampleHeight = CalculateWaterHeight(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}

#endif