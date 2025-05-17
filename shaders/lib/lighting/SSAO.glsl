/* Screen-Space Ambient Occlusion */

#define SSAO_SAMPLES 6 // [1 2 3 4 5 6 7 8 9 10 12 16 18 20 22 24 26 28 30 32 48 64]
#define SSAO_STRENGTH 1.0 // [0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

//================================================================================================//

float CalculateSSAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	const float rSteps = 1.0 / float(SSAO_SAMPLES);
	float maxSqLen = sqr(viewPos.z) * 0.25;
	float rMaxSqLen = 1.0 / maxSqLen;

	vec2 radius = vec2(0.0);
	vec2 rayStep = inversesqrt(sdot(viewPos)) * gbufferProjection[1][1] * vec2(0.5, 0.5 * aspectRatio);

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 rot = sincos(dither * TAU) * rSteps;
	float sum = 0.0;

	for (uint i = 0u; i < SSAO_SAMPLES; ++i, rot *= goldenRotate) {
		radius += rayStep;

		// vec3 rayPos = cosineWeightedHemisphereSample(n, RandNext2F()) * radius + viewPos;
		// vec3 difference = ScreenToViewSpace(ViewToScreenSpaceRaw(rayPos).xy) - viewPos;
		vec3 difference = ScreenToViewSpace(coord + rot * radius) - viewPos;
		float diffSqLen = sdot(difference);
		if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
			float NdotL = saturate(dot(normal, difference * inversesqrt(diffSqLen)));
			sum += NdotL * saturate(1.0 - diffSqLen * rMaxSqLen);
		}

		difference = ScreenToViewSpace(coord - rot * radius) - viewPos;
		diffSqLen = sdot(difference);
		if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
			float NdotL = saturate(dot(normal, difference * inversesqrt(diffSqLen)));
			sum += NdotL * saturate(1.0 - diffSqLen * rMaxSqLen);
		}
	}

	return saturate(1.0 - sum * rSteps * SSAO_STRENGTH);
}

#if defined DISTANT_HORIZONS
float CalculateSSAODH(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	const float rSteps = 1.0 / float(SSAO_SAMPLES);
	float maxSqLen = sqr(viewPos.z) * 0.25;
	float rMaxSqLen = 1.0 / maxSqLen;

	vec2 radius = vec2(0.0);
	vec2 rayStep = inversesqrt(sdot(viewPos)) * dhProjection[1][1] * vec2(0.5, 0.5 * aspectRatio);

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 rot = sincos(dither * TAU) * rSteps;
	float sum = 0.0;

	for (uint i = 0u; i < SSAO_SAMPLES; ++i, rot *= goldenRotate) {
		radius += rayStep;

		// vec3 rayPos = cosineWeightedHemisphereSample(n, RandNext2F()) * radius + viewPos;
		// vec3 difference = ScreenToViewSpace(ViewToScreenSpaceRaw(rayPos).xy) - viewPos;
		vec3 difference = ScreenToViewSpaceDH(coord + rot * radius) - viewPos;
		float diffSqLen = sdot(difference);
		if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
			float NdotL = saturate(dot(normal, difference * inversesqrt(diffSqLen)));
			sum += NdotL * saturate(1.0 - diffSqLen * rMaxSqLen);
		}

		difference = ScreenToViewSpaceDH(coord - rot * radius) - viewPos;
		diffSqLen = sdot(difference);
		if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
			float NdotL = saturate(dot(normal, difference * inversesqrt(diffSqLen)));
			sum += NdotL * saturate(1.0 - diffSqLen * rMaxSqLen);
		}
	}
#endif