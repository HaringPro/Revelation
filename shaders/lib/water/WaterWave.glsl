
float textureSmooth(in vec2 coord) {
	coord += 0.5;

	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part - 0.5;

	return texture(noisetex, coord * rcp(256.0)).x;
}

float CalculateWaterWaves(in vec2 position) {
    float wavesTime = frameTimeCounter * 2.0 * WATER_WAVE_SPEED;
	position.y *= 0.8;

    float wave = 0.0;
	wave += textureSmooth((position + vec2(wavesTime, position.x)) * 0.7);
	wave += textureSmooth((position + vec2(wavesTime * 1.2,  - position.x)) * 1.4) * 0.5;
	wave += textureSmooth((position + vec2(wavesTime, position.x)) * 2.2) * 0.2;
	wave += textureSmooth((position + vec2(wavesTime * 1.4,  - position.x)) * 3.2) * 0.1;

	return exp2(-wave) / (0.2 + dot(abs(dFdx(position) + dFdy(position)), vec2(64.0 / far)));
}

vec3 CalculateWaterNormal(in vec2 position) {
	float wavesCenter = CalculateWaterWaves(position);
	float wavesLeft   = CalculateWaterWaves(position + vec2(0.04, 0.0));
	float wavesUp     = CalculateWaterWaves(position + vec2(0.0, 0.04));

	vec2 wavesNormal = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 0.6));
}

vec3 CalculateWaterNormal(in vec2 position, in vec3 tangentViewDir) {
	vec3 stepSize = tangentViewDir / -tangentViewDir.z * vec3(vec2(0.1 * WATER_WAVE_HEIGHT), 1.0);

    vec3 samplePos = vec3(position, 1.0) + stepSize;
	float sampleHeight = CalculateWaterWaves(samplePos.xy);

	for (uint i = 0u; sampleHeight < samplePos.z && i < 60u; ++i) {
        samplePos += stepSize;
		sampleHeight = CalculateWaterWaves(samplePos.xy);
	}

	return CalculateWaterNormal(samplePos.xy);
}
