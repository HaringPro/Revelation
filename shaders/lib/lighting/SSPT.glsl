/* Screen-Space Path Tracing */

#define SSPT_SPP 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define INF 1
#define SSPT_BOUNCES INF // [INF]

#define SSPT_RR_MIN_BOUNCES 1 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define SSPT_BLENDED_LIGHTMAP 0.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]

//================================================================================================//

vec3 sampleRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return vec3(1e6);

	vec3 endPos = ViewToScreenSpace(viewDir + viewPos);
	vec3 rayDir = normalize(endPos - rayPos);

	float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rcp(16.0);

	vec3 rayStep = rayDir * stepLength;
	rayPos += rayStep * dither;

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;

	for (uint i = 0u; i < 16u; ++i, rayPos += rayStep) {
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;
		float sampleDepth = loadDepth0(ivec2(rayPos.xy));

		if (sampleDepth < rayPos.z) {
			float sampleDepthLinear = ScreenToViewDepth(sampleDepth);
			float traceDepthLinear = ScreenToViewDepth(rayPos.z);
			#if defined DISTANT_HORIZONS
				if (sampleDepth > 0.999999) sampleDepthLinear = ScreenToViewDepthDH(loadDepth0DH(ivec2(rayPos.xy)));
			#endif

			if (traceDepthLinear - sampleDepthLinear > 0.2 * traceDepthLinear) return vec3(rayPos.xy, sampleDepth);
		}
	}

	return vec3(1e6);
}

float CalculateBlocklightFalloff(in float blocklight) {
	float fade = rcp(sqr(16.0 - 15.0 * blocklight));
	blocklight += approxSqrt(blocklight) * 0.4 + sqr(blocklight) * 0.6;
	return blocklight * 0.5 * fade;
}

struct TracingData {
	vec3 rayPos;
    vec3 rayDir;
    vec3 viewNormal;
    vec3 worldNormal;
	vec3 contribution;
};

vec3 CalculateSSPT(in vec3 screenPos, in vec3 viewPos, in vec3 worldNormal, in vec2 lightmap) {
	lightmap.x = CalculateBlocklightFalloff(lightmap.x) * SSPT_BLENDED_LIGHTMAP;
	lightmap.y *= lightmap.y * lightmap.y;

	mat3 gbufferModelView = mat3(gbufferModelView);
    vec3 viewNormal = gbufferModelView * worldNormal;

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));

    #if defined DISTANT_HORIZONS
        float screenDepthMax = ViewToScreenDepth(ScreenToViewDepthDH(1.0));
    #else
        #define screenDepthMax 1.0
    #endif

	vec3 sum = vec3(0.0);

	#if SSPT_BOUNCES > 1
	// Multiple bounce tracing.

    for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
		// Initialize tracing data.
		TracingData target = TracingData(screenPos, vec3(0.0), viewNormal, worldNormal, vec3(1.0));

		for (uint bounce = 1u; bounce <= SSPT_BOUNCES; ++bounce) {
			vec3 sampleDir = sampleCosineVector(target.worldNormal, nextVec2(noiseGenerator));

			// target.rayDir = dot(target.worldNormal, target.rayDir) < 0.0 ? -target.rayDir : target.rayDir;
			target.rayDir = normalize(gbufferModelView * sampleDir);

			float dither = nextFloat(noiseGenerator);
			vec3 targetViewPos = ScreenToViewSpaceRaw(target.rayPos) + target.viewNormal * 1e-2;
			target.rayPos = sampleRaytrace(targetViewPos, target.rayDir, dither, target.rayPos);

			if (target.rayPos.z < screenDepthMax) {
				ivec2 targetTexel = ivec2(target.rayPos.xy);
				vec3 sampleRadiance = texelFetch(colortex4, targetTexel >> 1, 0).rgb;

				target.worldNormal = FetchWorldNormal(loadGbufferData0(targetTexel));
				target.viewNormal = gbufferModelView * target.worldNormal;;

				sum += sampleRadiance * target.contribution;

				target.contribution *= loadAlbedo(targetTexel);
				target.rayPos.xy *= viewPixelSize;
			} else if (dot(lightmap, vec2(1.0)) > 1e-5) {
				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir) + vec2(0.0, 0.5)).rgb;
				sum += (skyRadiance * lightmap.y + lightmap.x) * target.contribution;
				break;
			}

            // Russian roulette
			if (bounce >= SSPT_RR_MIN_BOUNCES) {
				float probability = saturate(luminance(target.contribution));
				if (probability < dither) break;
				target.contribution *= rcp(probability);
			}
		}
	}

	#else
	// Single bounce tracing.

	for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
			vec3 sampleDir = sampleCosineVector(worldNormal, nextVec2(noiseGenerator));

			vec3 rayDir = normalize(gbufferModelView * sampleDir);
			// rayDir = dot(viewNormal, rayDir) < 0.0 ? -rayDir : rayDir;

			vec3 hitPos = sampleRaytrace(viewPos + viewNormal * 1e-2, rayDir, nextFloat(noiseGenerator), screenPos);

			if (hitPos.z < screenDepthMax) {
				vec3 sampleRadiance = texelFetch(colortex4, ivec2(hitPos.xy * 0.5), 0).rgb;

				sum += sampleRadiance;
			} else if (dot(lightmap, vec2(1.0)) > 1e-5) {
				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir) + vec2(0.0, 0.5)).rgb;
				sum += skyRadiance * lightmap.y + lightmap.x;
			}
		}
	#endif

	return sum * rcp(float(SSPT_SPP));
}