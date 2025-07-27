/* Screen-Space Ambient Occlusion */

#define SSAO_SAMPLES 12 // [1 2 3 4 5 6 7 8 9 10 12 16 18 20 22 24 26 28 30 32 48 64]
#define SSAO_STRENGTH 1.5 // [0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

//================================================================================================//

float CalculateSSAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	const float rSteps = 1.0 / float(SSAO_SAMPLES);
	float maxSqLen = sqr(viewPos.z) * 0.25;
	float rMaxSqLen = 1.0 / maxSqLen;

	vec2 radius = vec2(0.0);
	vec2 rayStep = diagonal2(gbufferProjection) / -viewPos.z;

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 dir = sincos(dither * TAU) * rSteps;
	float sum = 0.0;

	for (uint i = 0u; i < SSAO_SAMPLES; ++i, dir *= goldenRotate) {
		radius += rayStep;

		vec2 sampleCoord = coord + dir * radius;
		float sampleDepth = loadDepth0(uvToTexel(sampleCoord));
		if (sampleDepth < 0.56) continue;

		#if defined DISTANT_HORIZONS
			vec3 difference;
			if (sampleDepth > 1.0 - EPS) {
				sampleDepth = loadDepth0DH(uvToTexel(sampleCoord));
				difference = ScreenToViewSpaceDH(vec3(sampleCoord, sampleDepth)) - viewPos;
			} else {
				difference = ScreenToViewSpace(vec3(sampleCoord, sampleDepth)) - viewPos;
			}
		#else
			vec3 difference = ScreenToViewSpace(vec3(sampleCoord, sampleDepth)) - viewPos;
		#endif

		float diffSqLen = sdot(difference);
		if (diffSqLen > EPS && diffSqLen < maxSqLen) {
			float cosAngle = saturate(dot(normal, difference * inversesqrt(diffSqLen)));
			sum += cosAngle * saturate(1.0 - diffSqLen * rMaxSqLen);
		}
	}

	return sqr(saturate(1.0 - sum * rSteps * SSAO_STRENGTH));
}