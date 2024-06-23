
float GetSmoothNoise(in vec2 coord) {
	coord += 0.5 / 256.0;

	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part - 0.5;

	return textureLod(noisetex, coord * rcp(256.0), 0.0).w;
}

// float CalculateWaterHeight(in vec2 position) {
//     float wavesTime = frameTimeCounter * 2.0 * WATER_WAVE_SPEED;

// 	// Apply a large scale noise to the position to create a more stochastic looking wave
// 	position += exp2(0.5 - 2.0 * pow5(1.0 - GetSmoothNoise(position * 0.15)));

//     float wave = GetSmoothNoise((position + wavesTime * 0.6) * vec2(0.9, 0.6));
// 	wave += GetSmoothNoise((position + vec2(wavesTime, position.x + wavesTime * 0.6)) * vec2(1.2, 1.8)) * 0.6;
// 	wave += GetSmoothNoise((position + vec2(wavesTime * 0.4, wavesTime - position.x * 0.7)) * vec2(2.0, 1.2)) * 0.3;
// 	wave += GetSmoothNoise((position + vec2(wavesTime * 0.8, position.x * 0.5 + wavesTime * 0.2)) * vec2(3.2, 2.7)) * 0.16;
// 	wave += GetSmoothNoise((position + vec2(wavesTime * 0.3, wavesTime - position.x * 0.3)) * vec2(4.4, 3.6)) * 0.1;

// 	return exp2(2.0 - wave * wave);
// }

float CalculateWaterHeight(in vec2 p) {
    float wavesTime = frameTimeCounter * 1.6 * WATER_WAVE_SPEED;
	p.y *= 0.8;

	// Apply a large scale noise to the position to create a more stochastic looking wave
	// p += exp2(1.0 - 3.0 * pow5(1.0 - GetSmoothNoise(p * 0.15)));

    float wave = 0.0;
	wave += GetSmoothNoise((p + vec2(wavesTime * 0.4, p.x - wavesTime)) * 0.7);
	wave += GetSmoothNoise((p - vec2(wavesTime, p.x)) * 1.6) * 0.5;
	wave += GetSmoothNoise((p + vec2(wavesTime * 0.4, p.x - wavesTime)) * 2.4) * 0.2;
	wave += GetSmoothNoise((p - vec2(wavesTime, p.x)) * 3.6) * 0.12;

    return wave * 4.0;
}

vec3 CalculateWaterNormal(in vec2 position) {
	float wavesCenter = CalculateWaterHeight(position);
	float wavesLeft   = CalculateWaterHeight(position + vec2(0.04, 0.0));
	float wavesUp     = CalculateWaterHeight(position + vec2(0.0, 0.04));

	vec2 wavesNormal = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 1.0));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	vec3 stepSize = tangentViewDir * vec3(vec2(0.1 * WATER_WAVE_HEIGHT), 1.0);
	stepSize *= rcp(64.0) / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 0.0) + stepSize;
	float sampleHeight = CalculateWaterHeight(samplePos.xy);

	while (sampleHeight < samplePos.z) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterHeight(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}
