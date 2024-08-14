
float GetSmoothNoise(in vec2 coord) {
	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part + 0.5;

	return textureLod(noisetex, coord * rcp(256.0), 0.0).x;
}

#if 0
float CalculateWaterHeight(in vec2 position) {
    float wavesTime = frameTimeCounter * 2.0 * WATER_WAVE_SPEED;

	// Apply a large scale noise to the position to create a more stochastic looking wave
	position += exp2(0.5 - 2.0 * pow5(1.0 - GetSmoothNoise(position * 0.15)));

    float wave = GetSmoothNoise((position + wavesTime * 0.6) * vec2(0.9, 0.6));
	wave += GetSmoothNoise((position + vec2(wavesTime, position.x + wavesTime * 0.6)) * vec2(1.2, 1.8)) * 0.6;
	wave += GetSmoothNoise((position + vec2(wavesTime * 0.4, wavesTime - position.x * 0.7)) * vec2(2.0, 1.2)) * 0.3;
	wave += GetSmoothNoise((position + vec2(wavesTime * 0.8, position.x * 0.5 + wavesTime * 0.2)) * vec2(3.2, 2.7)) * 0.16;
	wave += GetSmoothNoise((position + vec2(wavesTime * 0.3, wavesTime - position.x * 0.3)) * vec2(4.4, 3.6)) * 0.1;

	return exp2(2.0 - wave * wave);
}
#else
float CalculateWaterHeight(in vec2 p) {
    float wavesTime = frameTimeCounter * WATER_WAVE_SPEED;
	p *= vec2(0.7, -0.6);

	// p += 1.0 - abs(textureLod(noisetex, (p + wavesTime) * 0.0006, 0.0).w * 2.0 - 1.0);

    float base = 0.2 + GetSmoothNoise((p + vec2(wavesTime * 0.1, wavesTime * 0.2 - p.x * 1.3)) * 0.3);

	float wave = 0.0;
	wave += GetSmoothNoise((p + vec2(wavesTime * 1.4, p.x * 1.6 + wavesTime * 0.2)) * 0.65 + base * 3.0) * 1.2;
	wave += GetSmoothNoise((p + vec2(wavesTime, wavesTime * 0.3 - p.x)) * 1.5 + base * 3.2)				 * 0.7;
	wave += GetSmoothNoise((p + vec2(wavesTime * 0.9, p.x * 1.2 - wavesTime * 0.3)) * 2.4 - base * 3.4)	 * 0.4;
	wave += GetSmoothNoise((p + vec2(wavesTime * 1.8, wavesTime * 0.2 - p.x * 1.2)) * 3.6 - base * 3.6)	 * 0.2;

	return base * exp2(wave * 1.8 - 1.0);
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
	float wavesLeft   = CalculateWaterHeight(position + vec2(0.1, 0.0));
	float wavesUp     = CalculateWaterHeight(position + vec2(0.0, 0.1));

	vec2 wavesNormal  = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 1.0));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	vec3 stepSize = tangentViewDir * vec3(vec2(WATER_WAVE_HEIGHT), 1.0);
	stepSize *= 0.02 / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 0.0) + stepSize;
	float sampleHeight = CalculateWaterHeight(samplePos.xy);

	while (sampleHeight < samplePos.z) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterHeight(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}
