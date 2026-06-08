// Reference:
// Morgan McGuire, Michael Mara. "Efficient GPU Screen-Space Ray Tracing". JCGT, 2014.
// https://jcgt.org/published/0003/04/04/paper.pdf

#if !defined INCLUDE_LIGHTING_SSRT
#define INCLUDE_LIGHTING_SSRT

#define SSRT_MAX_SAMPLES 16 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define SSRT_SKY_TRACING

#define SSRT_REFINEMENT
#define SSRT_REFINEMENT_STEPS 4 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

//================================================================================================//

bool ScreenSpaceRaytrace(vec3 viewOrigin, vec3 viewDir, float dither, uint steps, inout vec3 hitPos) {
	vec3 rayOrigin = hitPos;

	float maxDist = step(viewDir.z, 0.0) * 1e23 - (viewOrigin.z + near) / viewDir.z;
	vec3 rayDir = normalize(ViewToScreenPos(viewDir * maxDist + viewOrigin) - rayOrigin);
	rayDir *= minOf((step(0.0, rayDir) - rayOrigin) / rayDir);

	float rSteps = 1.0 / float(steps);
	vec3 rayStep = rayDir * rSteps;
	float invDirZ = rcp(abs(rayStep.z));

	float compareTolerance = 2.0 * max(abs(rayStep.z), (rayOrigin.z + gbufferProjection[2].z) * rSteps);

	#if defined LOD_MOD
		float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
	#else
		#define screenDepthSky 1.0
	#endif

	float t = dither;

	bool hit = false;
	for (uint i = 0u; i < steps; ++i) {
		hitPos = rayOrigin + rayStep * t;

		if (saturate(hitPos.xy) != hitPos.xy) break;
		if (hitPos.z >= screenDepthSky) {
		#ifdef SSRT_SKY_TRACING
			hit = true;
		#endif
			break;
		}

		ivec2 sampleTexel = uvToTexelScaled(hitPos.xy);
		float sampleDepth = loadDepth2(sampleTexel);
		#if defined LOD_MOD
			if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(sampleTexel)));
		#endif

		float depthDiff = sampleDepth - hitPos.z;
		if (abs(depthDiff + compareTolerance) < compareTolerance) {
			hit = true;
			break;
		}

		t += clamp(depthDiff * invDirZ, 0.01, 1.1);
	}

	#ifdef SSRT_REFINEMENT
	if (hit) {
		// Refine hit position (binary search)
		for (uint i = 0u; i < SSRT_REFINEMENT_STEPS; ++i) {
			rayStep *= 0.5;

			ivec2 sampleTexel = uvToTexelScaled(hitPos.xy);
			float sampleDepth = loadDepth2(sampleTexel);
			#if defined LOD_MOD
				if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(sampleTexel)));
			#endif

			float depthDiff = sampleDepth - hitPos.z;
			if (abs(depthDiff + compareTolerance) < compareTolerance) {
				hitPos -= rayStep;
			} else {
				hitPos += rayStep;
			}
		}
	}
	#endif

	return hit;
}

#endif // INCLUDE_LIGHTING_SSRT
