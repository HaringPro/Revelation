// Reference:
// Morgan McGuire, Michael Mara. "Efficient GPU Screen-Space Ray Tracing". JCGT, 2014.
// https://jcgt.org/published/0003/04/04/paper.pdf

#define SSRT_MAX_SAMPLES 16 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define SSRT_SKY_TRACING

#define SSRT_REFINEMENT
#define SSRT_REFINEMENT_STEPS 4 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

//================================================================================================//

bool ScreenSpaceRaytrace(vec3 viewPos, vec3 viewDir, float dither, uint steps, inout vec3 screenPos) {
	vec3 rayOrigin = screenPos;

	float fixZ = step(viewDir.z, 0.0) * 1e23 - (viewPos.z + near) / viewDir.z;
	vec3 rayDir = normalize(ViewToScreenPos(viewDir * fixZ + viewPos) - rayOrigin);
	rayDir *= minOf((step(0.0, rayDir) - screenPos) / rayDir);

	float rSteps = 1.0 / float(steps);
	float invDirZ = rcp(abs(rayDir.z));
	vec3 rayStep = rayDir * rSteps;

	float compareTolerance = max(abs(rayStep.z), (rayOrigin.z + gbufferProjection[2].z) * rSteps);

	#if defined LOD_MOD
		float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
	#else
		#define screenDepthSky 1.0
	#endif

	bool hit = false;

	float t = dither * rSteps;
	float stepMin = rSteps * 0.01;
	float stepMax = rSteps * 1.1;

	for (uint i = 0u; i < steps; ++i) {
		vec3 rayPos = rayOrigin + rayDir * t;

		if (saturate(rayPos.xy) != rayPos.xy) break;
		if (rayPos.z >= screenDepthSky) {
		#ifdef SSRT_SKY_TRACING
			screenPos = rayPos;
			hit = true;
		#endif
			break;
		}

		ivec2 sampleTexel = scaleTexelPos(uvToTexel(rayPos.xy));
		float sampleDepth = loadDepth2(sampleTexel);
		#if defined LOD_MOD
			if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(sampleTexel)));
		#endif

		float depthDiff = sampleDepth - rayPos.z;
		if (abs(depthDiff + compareTolerance) < compareTolerance) {
			screenPos = rayPos;
			hit = true;
			break;
		}

		t += clamp(depthDiff * invDirZ, stepMin, stepMax);
	}

	#ifdef SSRT_REFINEMENT
	if (hit) {
		// Refine hit position (binary search)
		for (uint i = 0u; i < SSRT_REFINEMENT_STEPS; ++i) {
			rayStep *= 0.5;

			ivec2 sampleTexel = scaleTexelPos(uvToTexel(screenPos.xy));
			float sampleDepth = loadDepth2(sampleTexel);
			#if defined LOD_MOD
				if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(sampleTexel)));
			#endif

			float depthDiff = sampleDepth - screenPos.z;
			if (abs(depthDiff + compareTolerance) < compareTolerance) {
				screenPos -= rayStep;
			} else {
				screenPos += rayStep;
			}
		}
	}
	#endif

	return hit;
}
