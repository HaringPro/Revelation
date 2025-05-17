/* Ground-Truth Ambient Occlusion */
// Reference: https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf

#define GTAO_SLICES	2 // [1 2 3 4 5 6 8 10 12 15 17 20]
#define GTAO_DIRECTION_SAMPLES 4 // [1 2 3 4 5 6 8 10 12 15 17 20]

#define GTAO_RADIUS 1.0 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]

//================================================================================================//

float CalculateGTAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	float viewDistance = max(1.0, sdot(viewPos)); // Trick to avoid artifacts
	float norm = inversesqrt(viewDistance);
	viewDistance *= norm;

	vec3 viewDir = viewPos * -norm;

	const int sliceCount = GTAO_SLICES;
	const float rSliceCount = 1.0 / float(sliceCount);

	const int sampleCount = GTAO_DIRECTION_SAMPLES;
	const float rSampleCount = 1.0 / float(sampleCount);

	float radius = GTAO_RADIUS * saturate(0.25 + viewDistance * rcp(128.0));
	vec2 sRadius = rSampleCount * radius * gbufferProjection[1][1] * norm * vec2(1.0, aspectRatio);
	float falloff = 4.0 * norm;

	float visibility = 0.0;

	for (int slice = 0; slice < sliceCount; ++slice) {
		float slicePhi = (float(slice) + dither) * PI * rSliceCount;

		vec3 directionV = vec3(cos(slicePhi), sin(slicePhi), 0.0);
		vec3 orthoDirectionV = directionV - dot(directionV, viewDir) * viewDir;
		vec3 axisV = cross(directionV, viewDir);
		vec3 projNormalV = normal - axisV * dot(normal, axisV);

		float lenV = sdot(projNormalV);
		float normV = inversesqrt(lenV);
		lenV *= normV;

		float sgnN = fastSign(dot(orthoDirectionV, projNormalV));
		float cosN = saturate(dot(projNormalV, viewDir) * normV);
		float n = sgnN * fastAcos(cosN);

		vec2 cHorizonCos = vec2(-1.0);

		for (int samp = 0; samp < sampleCount; ++samp) {
			vec2 stepDir = directionV.xy * sRadius;
			float stepDither = R1(slice + samp * sliceCount, dither);
			vec2 offset = (float(samp) + stepDither) * stepDir;

			vec2 sTexCoord = coord + offset;
			vec3 sHorizonV = ScreenToViewSpace(sTexCoord) - viewPos;

			float sLenV = sdot(sHorizonV);
			float sNormV = inversesqrt(sLenV);
			sLenV *= sNormV;

			float sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
			sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff - 3.0));

			cHorizonCos.x = max(sHorizonCos, cHorizonCos.x);

			sTexCoord = coord - offset;
			sHorizonV = ScreenToViewSpace(sTexCoord) - viewPos;

			sLenV = sdot(sHorizonV);
			sNormV = inversesqrt(sLenV);
			sLenV *= sNormV;

			sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
			sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff - 3.0));

			cHorizonCos.y = max(sHorizonCos, cHorizonCos.y);
		}

		vec2 h = n + clamp(vec2(fastAcos(cHorizonCos.x), -fastAcos(cHorizonCos.y)) - n, -hPI, hPI);
		h = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n);

		visibility += lenV * (h.x + h.y);
	}

	return 0.25 * visibility * rSliceCount;
}

#if defined DISTANT_HORIZONS
float CalculateGTAODH(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	float viewDistance = max(1.0, sdot(viewPos)); // Trick to avoid artifacts
	float norm = inversesqrt(viewDistance);
	viewDistance *= norm;

	vec3 viewDir = viewPos * -norm;

	const int sliceCount = GTAO_SLICES;
	const float rSliceCount = 1.0 / float(sliceCount);

	const int sampleCount = GTAO_DIRECTION_SAMPLES;
	const float rSampleCount = 1.0 / float(sampleCount);

	float radius = GTAO_RADIUS * saturate(0.25 + viewDistance * rcp(128.0));
	vec2 sRadius = rSampleCount * radius * dhProjection[1][1] * norm * vec2(1.0, aspectRatio);
	float falloff = 4.0 * norm;

	float visibility = 0.0;

	for (int slice = 0; slice < sliceCount; ++slice) {
		float slicePhi = (float(slice) + dither) * PI * rSliceCount;

		vec3 directionV = vec3(cos(slicePhi), sin(slicePhi), 0.0);
		vec3 orthoDirectionV = directionV - dot(directionV, viewDir) * viewDir;
		vec3 axisV = cross(directionV, viewDir);
		vec3 projNormalV = normal - axisV * dot(normal, axisV);

		float lenV = sdot(projNormalV);
		float normV = inversesqrt(lenV);
		lenV *= normV;

		float sgnN = fastSign(dot(orthoDirectionV, projNormalV));
		float cosN = saturate(dot(projNormalV, viewDir) * normV);
		float n = sgnN * fastAcos(cosN);

		vec2 cHorizonCos = vec2(-1.0);

		for (int samp = 0; samp < sampleCount; ++samp) {
			vec2 stepDir = directionV.xy * sRadius;
			float stepDither = R1(slice + samp * sliceCount, dither);
			vec2 offset = (float(samp) + stepDither) * stepDir;

			vec2 sTexCoord = coord + offset;
			vec3 sHorizonV = ScreenToViewSpaceDH(sTexCoord) - viewPos;

			float sLenV = sdot(sHorizonV);
			float sNormV = inversesqrt(sLenV);
			sLenV *= sNormV;

			float sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
			sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff - 3.0));

			cHorizonCos.x = max(sHorizonCos, cHorizonCos.x);

			sTexCoord = coord - offset;
			sHorizonV = ScreenToViewSpaceDH(sTexCoord) - viewPos;

			sLenV = sdot(sHorizonV);
			sNormV = inversesqrt(sLenV);
			sLenV *= sNormV;

			sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
			sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff - 3.0));

			cHorizonCos.y = max(sHorizonCos, cHorizonCos.y);
		}

		vec2 h = n + clamp(vec2(fastAcos(cHorizonCos.x), -fastAcos(cHorizonCos.y)) - n, -hPI, hPI);
		h = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n);

		visibility += lenV * (h.x + h.y);
	}

	return 0.25 * visibility * rSliceCount;
}
#endif

vec3 ApproxMultiBounce(in float ao, in vec3 albedo) {
	vec3 a = 2.0404 * albedo - 0.3324;
	vec3 b = 4.7951 * albedo - 0.6417;
	vec3 c = 2.7552 * albedo + 0.6903;

	return max(vec3(ao), ((ao * a - b) * ao + c) * ao);
}