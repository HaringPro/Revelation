
float textureSmooth(in vec2 coord) {
	coord += 0.5;

	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part - 0.5;

	return texture(noisetex, coord * rcp(256.0)).x;
}

float CalculateWaterWaves(in vec2 position) {
    float wavesTime = frameTimeCounter * 1.5 * WATER_WAVE_SPEED;

	// Apply a large scale noise to the position to create a more stochastic looking wave
	position += max(exp2(1.2 - 1.5 * pow5(1.0 - textureSmooth((position - wavesTime) * 0.3))), 0.2);

    float wave = 0.0;
	wave += textureSmooth((position + vec2(wavesTime, position.x)) * vec2(0.6, 1.2));
	wave += textureSmooth((position + vec2(wavesTime * 1.2,  - position.x)) * vec2(2.0, 1.0)) * 0.5;
	wave += textureSmooth((position + vec2(wavesTime, position.x)) * 2.2) * 0.2;
	wave += textureSmooth((position + vec2(wavesTime * 1.4,  - position.x)) * 3.2) * 0.1;

	return exp2(-wave * wave) / (0.2 + dot(abs(dFdx(position) + dFdy(position)), vec2(80.0 / far)));
}

vec3 CalculateWaterNormal(in vec2 position) {
	float wavesCenter = CalculateWaterWaves(position);
	float wavesLeft   = CalculateWaterWaves(position + vec2(0.04, 0.0));
	float wavesUp     = CalculateWaterWaves(position + vec2(0.0, 0.04));

	vec2 wavesNormal = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 0.8));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	vec3 stepSize = tangentViewDir * vec3(vec2(2e-3 * WATER_WAVE_HEIGHT), 1.0);
	stepSize *= 0.02 / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 1.0) + stepSize;
	float sampleHeight = CalculateWaterWaves(samplePos.xy);

	for (uint i = 1u; sampleHeight < samplePos.z && i < 50u; ++i) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterWaves(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}
