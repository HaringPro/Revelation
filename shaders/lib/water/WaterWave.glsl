
float textureSmooth(in vec2 coord) {
	coord += 0.5;

	vec2 whole = floor(coord);
	vec2 part  = curve(coord - whole);

	coord = whole + part - 0.5;

	return texture(noisetex, coord * rcp(256.0)).x;
}

float WaterHeight(in vec2 p) {
    float wavesTime = frameTimeCounter * 1.5 * WATER_WAVE_SPEED;
	p.y *= 0.8;

    float wave = 0.0;
	wave += textureSmooth((p + vec2(wavesTime, p.x - wavesTime)) * 0.7);
	wave += textureSmooth((p - vec2(wavesTime * 0.4, p.x - wavesTime * 0.4)) * 1.4) * 0.5;
	wave += textureSmooth((p + vec2(wavesTime, p.x - wavesTime)) * 2.2) * 0.2;
	wave += textureSmooth((p - vec2(wavesTime * 0.4, p.x + wavesTime * 0.4)) * 3.2) * 0.1;

	return wave / (0.8 + dot(abs(dFdx(p) + dFdy(p)), vec2(2e2 / far)));
}

vec3 GetWavesNormal(in vec2 position) {
	float wavesCenter = WaterHeight(position);
	float wavesLeft   = WaterHeight(position + vec2(0.04, 0.0));
	float wavesUp     = WaterHeight(position + vec2(0.0, 0.04));

	vec2 wavesNormal = vec2(wavesCenter - wavesLeft, wavesCenter - wavesUp);

	return normalize(vec3(wavesNormal * WATER_WAVE_HEIGHT, 0.5));
}
