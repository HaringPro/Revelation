
#if AO_ENABLED == 1
	// Screen space ambient occlusion
	#define SSAO_SAMPLES 	6 	// [1 2 3 4 5 6 7 8 9 10 12 16 18 20 22 24 26 28 30 32 48 64]
	#define SSAO_STRENGTH 	1.0 // [0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

	float CalculateSSAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither) {
		float rSteps = 1.0 / float(SSAO_SAMPLES);
		float maxSqLen = sqr(viewPos.z) * 0.25;

		vec2 radius = vec2(0.0);
		vec2 rayStep = vec2(0.4, 0.4 * aspectRatio) / max((far - near) * -viewPos.z / far + near, 5.0) * gbufferProjection[1][1];

		const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

		vec2 rot = sincos(dither * TAU) * rSteps;
		float total = 0.0;

		for (uint i = 0u; i < SSAO_SAMPLES; ++i, rot *= goldenRotate) {
			radius += rayStep;

			// vec3 rayPos = cosineWeightedHemisphereSample(n, RandNext2F()) * radius + viewPos;
			// vec3 diff = ScreenToViewSpace(ViewToScreenSpaceRaw(rayPos).xy) - viewPos;
			vec3 diff = ScreenToViewSpace(coord + rot * radius) - viewPos;
			float diffSqLen = dotSelf(diff);
			if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
				float NdotL = saturate(dot(normal, diff * inversesqrt(diffSqLen)));
				total += NdotL * saturate(1.0 - diffSqLen / maxSqLen);
			}

			diff = ScreenToViewSpace(coord - rot * radius) - viewPos;
			diffSqLen = dotSelf(diff);
			if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
				float NdotL = saturate(dot(normal, diff * inversesqrt(diffSqLen)));
				total += NdotL * saturate(1.0 - diffSqLen / maxSqLen);
			}
		}

		total = max0(1.0 - total * rSteps * SSAO_STRENGTH);
		return total;
	}

#elif AO_ENABLED == 2
	// Ground-truth ambient occlusion
	#define GTAO_SLICE_SAMPLES		3 	// [1 2 3 4 5 6 8 10 12 15 17 20]
	#define GTAO_DIRECTION_SAMPLES	3 	// [1 2 3 4 5 6 8 10 12 15 17 20]

	#define GTAO_RADIUS 			0.5 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

	// Reference: https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf
	float CalculateGTAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in float dither){
		vec3 viewDir = normalize(-viewPos);

		const int sliceCount = GTAO_SLICE_SAMPLES;
		const float rSliceCount = 1.0 / float(sliceCount);

		const int directionSampleCount = GTAO_DIRECTION_SAMPLES;
		const float rDirectionSampleCount = 1.0 / float(directionSampleCount);

		float falloff = gbufferProjection[1][1] / -viewPos.z * 0.6;
		vec2 radius = max(GTAO_RADIUS * falloff, 0.1) * vec2(1.0, aspectRatio);

		float visibility = 0.0;

		for (int slice = 0; slice < sliceCount; ++slice) {
			float slicePhi = (slice + dither) * PI * rSliceCount;

			vec3 directionV = vec3(cos(slicePhi), sin(slicePhi), 0.0);
			vec3 orthoDirectionV = directionV - dot(directionV, viewDir) * viewDir;
			vec3 axisV = cross(directionV, viewDir);
			vec3 projNormalV = normal - axisV * dot(normal, axisV);

			float lenV = dotSelf(projNormalV);
			float normV = inversesqrt(lenV);
			lenV *= normV;

			float sgnN = sign(dot(orthoDirectionV, projNormalV));
			float cosN = saturate(dot(projNormalV, viewDir) * normV);
			float n = sgnN * fastAcos(cosN);

			vec2 cHorizonCos = vec2(-1.0);

			for (int samp = 0; samp < directionSampleCount; ++samp) {
				vec2 offset = (samp + R1(slice + samp * frameCounter, dither)) * rDirectionSampleCount * directionV.xy * radius;

				vec2 sTexCoord = coord + offset;
				vec3 sHorizonV = ScreenToViewSpace(sTexCoord) - viewPos;

				float sLenV = dotSelf(sHorizonV);
				float sNormV = inversesqrt(sLenV);
				sLenV *= sNormV;

				float sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
				sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff));

				cHorizonCos.x = max(sHorizonCos, cHorizonCos.x);

				sTexCoord = coord - offset;
				sHorizonV = ScreenToViewSpace(sTexCoord) - viewPos;

				sLenV = dotSelf(sHorizonV);
				sNormV = inversesqrt(sLenV);
				sLenV *= sNormV;

				sHorizonCos = dot(sHorizonV, viewDir) * sNormV;
				sHorizonCos = mix(sHorizonCos, -1.0, saturate(sLenV * falloff));

				cHorizonCos.y = max(sHorizonCos, cHorizonCos.y);
			}

			vec2 h = n + clamp(vec2(fastAcos(cHorizonCos.x), -fastAcos(cHorizonCos.y)) - n, -hPI, hPI);
			h = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n);

			visibility += 0.25 * lenV * (h.x + h.y);
		}

		return visibility * rSliceCount;
	}
#endif