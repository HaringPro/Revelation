/* Ground-Truth Ambient Occlusion */
// Reference: https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf

#define GTAO_SLICES	2 // [1 2 3 4 5 6 8 10 12 15 17 20]
#define GTAO_DIRECTION_SAMPLES 4 // [1 2 3 4 5 6 8 10 12 15 17 20]

#define GTAO_RADIUS 2.0 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]

//================================================================================================//

void SampleHorizonCos(in vec2 coord, in vec2 offset, in vec3 viewPos, in vec3 viewDir, in vec2 falloff, inout float cHorizonCos) {
	vec2 sTexCoord = coord + offset;
	float sDepth = loadDepth0(uvToTexel(sTexCoord));
	if (sDepth < 0.56) return;

	#if defined DISTANT_HORIZONS
		vec3 sHorizonV;
		if (sDepth > 1.0 - EPS) {
			sDepth = loadDepth0DH(uvToTexel(sTexCoord));
			sHorizonV = ScreenToViewSpaceDH(vec3(sTexCoord, sDepth)) - viewPos;
		} else {
			sHorizonV = ScreenToViewSpace(vec3(sTexCoord, sDepth)) - viewPos;
		}
	#else
		vec3 sHorizonV = ScreenToViewSpace(vec3(sTexCoord, sDepth)) - viewPos;
	#endif

	float sLenV = sdot(sHorizonV);
	float sNormV = inversesqrt(sLenV);

	float sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
	sHorizonCos = mix(sHorizonCos, cHorizonCos, remap(falloff.x, falloff.y, sLenV));
	cHorizonCos = max(sHorizonCos, cHorizonCos);
}

float CalculateGTAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
	float viewDistance = sdot(viewPos);
	float norm = inversesqrt(viewDistance);
	viewDistance *= norm;

	vec3 viewDir = viewPos * -norm;

	const int sliceCount = GTAO_SLICES;
	const float rSliceCount = 1.0 / float(sliceCount);

	const int sampleCount = GTAO_DIRECTION_SAMPLES;
	const float rSampleCount = 1.0 / float(sampleCount);

	float radius = GTAO_RADIUS * saturate(0.25 + viewDistance * rcp(64.0));
	vec2 sRadius = rSampleCount * radius * norm * diagonal2(gbufferProjection);
	vec2 falloff = sqr(radius * vec2(1.0, 4.0));

	float visibility = 0.0;

	for (uint slice = 0u; slice < sliceCount; ++slice) {
		float slicePhi = (float(slice) + dither) * (PI * rSliceCount);

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

		for (uint samp = 0u; samp < sampleCount; ++samp) {
			vec2 stepDir = directionV.xy * sRadius;
			float stepDither = R1(int(slice + samp * sliceCount), dither);
			vec2 offset = (float(samp) + stepDither) * stepDir;

			SampleHorizonCos(coord, offset, viewPos, viewDir, falloff, cHorizonCos.x);
			SampleHorizonCos(coord,-offset, viewPos, viewDir, falloff, cHorizonCos.y);
		}

		vec2 h = n + clamp(vec2(fastAcos(cHorizonCos.x), -fastAcos(cHorizonCos.y)) - n, -hPI, hPI);
		h = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n);

		visibility += lenV * (h.x + h.y);
	}

	return 0.25 * rSliceCount * visibility;
}

vec3 ApproxMultiBounce(in float ao, in vec3 albedo) {
	vec3 a = 2.0404 * albedo - 0.3324;
	vec3 b = 4.7951 * albedo - 0.6417;
	vec3 c = 2.7552 * albedo + 0.6903;

	return max(vec3(ao), ((ao * a - b) * ao + c) * ao);
}