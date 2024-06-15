
float textureSmooth(in vec2 coord) {
	coord += 0.5;

	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part - 0.5;

	return texture(noisetex, coord * rcp(256.0)).x;
}

float CalculateWaterWaves(in vec2 position) {
    float wavesTime = frameTimeCounter * 1.5 * WATER_WAVE_SPEED;

	position += wavesTime * vec2(-0.4, 0.2);
	// Apply a large scale noise to the position to create a more stochastic looking wave
	position += 1.0 - exp2(-4.0 * pow5(1.0 - textureSmooth(position * 0.2)));

    float wave = 0.0;
	position += vec2(wavesTime, position.x);
	wave += textureSmooth(position * vec2(0.6, 1.2));
	position -= vec2(wavesTime * 1.2,  position.x * 0.7);
	wave += textureSmooth(position * vec2(2.0, 1.0)) * 0.5;
	position += vec2(wavesTime * 0.8,  -position.x * 0.5);
	wave += textureSmooth(position * 2.2) * 0.2;
	position -= vec2(wavesTime * 1.6,  position.x * 0.3);
	wave += textureSmooth(position * 3.2) * 0.1;

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
	vec3 stepSize = tangentViewDir * vec3(vec2(0.2 * WATER_WAVE_HEIGHT), 1.0);
	stepSize *= rcp(32.0) / -tangentViewDir.z;

    vec3 samplePos = vec3(position, 0.0) + stepSize;
	float sampleHeight = CalculateWaterWaves(samplePos.xy);

	while (sampleHeight < samplePos.z) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterWaves(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}
