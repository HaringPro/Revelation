#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

float FetchNoise(in vec2 coord) {
	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part + 0.5;

	return textureLod(noisetex, coord * rcp(256.0), 0.0).x;
}

#if 0
float CalculateWaterHeight(in vec2 position) {
	float waveTime = frameTimeCounter * WATER_WAVE_SPEED;

	vec2 pos = vec2(0.4, 0.27) * position + vec2(0.8, 0.12) * waveTime;
	pos += pos.yx * vec2(0.2, 1.3);
	float waves = -2.0;

	pos = vec2(0.76, 0.51) * position + vec2(-0.2, -0.3) * waveTime;
	pos += pos.yx * vec2(0.1, 0.4);
	waves -= 0.16 * sin(FetchNoise(pos) * TAU);

	pos = vec2(1.4, 0.92) * position + vec2(1.1, -0.8) * waveTime;
	pos.y -= pos.x * 1.2;
	waves += (FetchNoise(pos) - 1.0) * 0.24;

	pos = vec2(3.5, 2.2) * position + vec2(2.2, 0.7) * waveTime;
	pos.y += pos.x * 0.6;
	waves += (FetchNoise(pos) - 1.0) * 0.09;

	pos = vec2(7.0, 3.9) * position + vec2(1.8, 0.8) * waveTime;
	pos.y -= pos.x;
	waves += (FetchNoise(pos) - 1.0) * 0.03;

	return waves;
}
#else
float CalculateWaterHeight(in vec2 position) {
	float waveTime = frameTimeCounter * WATER_WAVE_SPEED;

	vec2 pos = vec2(0.4, 0.27) * position + vec2(0.8, 0.12) * waveTime;
	pos += pos.yx * vec2(0.2, 1.3);
	float waves = FetchNoise(pos) * 2.0 - 1.0;
	waves = -2.0 * (waves * waves + 0.04);

	pos = vec2(0.76, 0.51) * position + vec2(-0.2, -0.3) * waveTime;
	pos += pos.yx * vec2(0.1, 0.4);
	waves -= 0.16 * sin(FetchNoise(pos) * TAU);

	pos = vec2(1.4, 0.92) * position + vec2(1.1, -0.8) * waveTime;
	pos.y -= pos.x * 1.2;
	waves += (FetchNoise(pos) - 1.0) * 0.24;

	pos = vec2(3.5, 2.2) * position + vec2(2.2, 0.7) * waveTime;
	pos.y += pos.x * 0.6;
	waves += (FetchNoise(pos) - 1.0) * 0.09;

	pos = vec2(7.0, 3.9) * position + vec2(1.8, 0.8) * waveTime;
	pos.y -= pos.x;
	waves += (FetchNoise(pos) - 1.0) * 0.03;

	return waves;
}
#endif


// https://www.shadertoy.com/view/MdXyzX
// Calculates wave value and its derivative, 
// for the wave direction, position in space, wave frequency and time
vec2 wavedx(vec2 position, vec2 direction, float noise, float frequency, float timeshift) {
	float x = dot(direction, position) * frequency + noise + timeshift;
	float wave = fastExp(sin(x) - 1.0);
	float dx = wave * cos(x);
	return vec2(wave, -dx);
}

// Calculates waves by summing octaves of various waves with various parameters
float getwaves(vec2 position) {
	float iter = 0.0; // this will help generating well distributed wave directions
	float frequency = 0.6; // frequency of the wave, this will change every iteration
	float timeMultiplier = 1.6; // time multiplier for the wave, this will change every iteration
	float weight = 1.0; // weight in final sum for the wave, this will change every iteration
	float sumOfValues = 0.0; // will store final sum of values
	float sumOfWeights = 0.0; // will store final sum of weights

	float noise = 5.0 * texture(noisetex, (position + frameTimeCounter) * 0.002).x;
	for (uint i = 0u; i < 12u; ++i) {
		// add some kind of random value to make next wave look random too
		iter += 1232.399963;

		// generate some wave direction that looks kind of random
		vec2 p = sincos(iter);
		// calculate wave data
		vec2 res = wavedx(position, p, noise, frequency, frameTimeCounter * timeMultiplier);

		// shift position around according to wave drag and derivative of the wave
		position += p * res.y * weight;

		// add the results to sums
		sumOfValues += res.x * weight;
		sumOfWeights += weight;

		// modify next octave
		weight *= 0.65;
		frequency *= 1.45;
		timeMultiplier *= 1.1;
	}
	// calculate and return
	return sumOfValues / sumOfWeights * 12.0;
}

//================================================================================================//

vec3 CalculateWaterNormal(in vec2 position) {
	float wavesCenter = CalculateWaterHeight(position);
	float wavesLeft   = CalculateWaterHeight(position + vec2(0.04, 0.0));
	float wavesUp     = CalculateWaterHeight(position + vec2(0.0, 0.04));

	vec2 wavesNormal  = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 0.15));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	vec3 stepSize = vec3(tangentViewDir.xy * WATER_WAVE_HEIGHT * 0.4, -0.02);
	stepSize.xy *= 0.02 / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 0.0) + stepSize;
	float sampleHeight = CalculateWaterHeight(samplePos.xy);

	while (sampleHeight < samplePos.z) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterHeight(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}

#endif