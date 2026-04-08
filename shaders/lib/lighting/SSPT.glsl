/* Screen-Space Path Tracing */
#define SSPT_ENABLED
#define SSPT_SPP 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define SSPT_BOUNCES 1 // [1]
#define SSPT_RT_STEPS 16 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60 62 64]

#define SSPT_RR_MIN_BOUNCES 1 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
in uint noiseGenerator;
//================================================================================================//

vec3 SampleRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return vec3(1e6);

	vec3 endPos = ViewToScreenPos(viewDir + viewPos);
	vec3 rayDir = normalize(endPos - rayPos);

	float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rcp(float(SSPT_RT_STEPS));

	vec3 rayStep = rayDir * stepLength;
	rayPos += rayStep * dither;

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;

	for (uint i = 0u; i < SSPT_RT_STEPS; ++i, rayPos += rayStep) {
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;
		float sampleDepth = loadDepth0(ivec2(rayPos.xy));

		if (sampleDepth < rayPos.z) {
			float sampleDepthLinear = ScreenToViewDepth(sampleDepth);
			float traceDepthLinear = ScreenToViewDepth(rayPos.z);
			#if defined LOD_MOD
				if (sampleDepth > 1.0 - EPS) sampleDepthLinear = ScreenToViewDepthLod(loadDepth0Lod(ivec2(rayPos.xy)));
			#endif

			if (traceDepthLinear - sampleDepthLinear > 0.2 * traceDepthLinear) return vec3(rayPos.xy, sampleDepth);
		}
	}

	return vec3(1e6);
}

vec3 CalculateSSPT(in vec3 screenPos, in vec3 viewPos, in vec3 worldNormal, in vec2 lightmap) {
	lightmap.y *= lightmap.y * lightmap.y;

    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));

    #if defined LOD_MOD
        float screenDepthMax = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
    #else
        #define screenDepthMax 1.0
    #endif

	vec3 sum = vec3(0.0);

    for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
		// for (uint bounce = 1u; bounce <= SSPT_BOUNCES; ++bounce) {
			vec3 rayDir = SampleCosineHemisphere(viewNormal, nextVec2(noiseGenerator));

			float dither = nextFloat(noiseGenerator);
			vec3 hitPos = SampleRaytrace(viewPos + viewNormal * 1e-2, rayDir, dither, screenPos);

			if (hitPos.z < screenDepthMax) {
				vec3 sampleRadiance = texelFetch(colortex4, ivec2(hitPos.xy) >> 1, 0).rgb;
				sum += sampleRadiance;
			} else if (lightmap.y > EPS) {
				vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
				vec3 skyRadiance = texture(skyMapTex, ProjectSky(rayDirWorld)).rgb;

				sum += skyRadiance * lightmap.y;
				break;
			}

            // Russian roulette
			// if (bounce >= SSPT_RR_MIN_BOUNCES) {
			// 	float probability = saturate(luminance(target.contribution));
			// 	if (probability < dither) break;
			// 	target.contribution *= rcp(probability);
			// }
		// }
	}

	return sum * rcp(float(SSPT_SPP));
}