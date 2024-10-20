
#define RAYTRACE_SAMPLES 18 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define REAL_SKY_REFLECTIONS

#define RAYTRACE_REFINEMENT
#define RAYTRACE_REFINEMENT_STEPS 6 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

#define RAYTRACE_ADAPTIVE_STEP

bool ScreenSpaceRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in uint steps, inout vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return false;

    float rSteps = 1.0 / float(steps);

    vec3 endPos = ViewToScreenSpace(viewDir + viewPos);
    vec3 rayDir = normalize(endPos - rayPos);
    float stepWeight = 1.0 / rayDir.z;

    float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rSteps;

    rayDir.xy *= viewSize;
    rayPos.xy *= viewSize;

    vec3 rayStep = rayDir * stepLength;

	float depthTolerance = max(0.2 * oneMinus(rayPos.z), -2.0 * rayStep.z);
    rayPos += rayStep * (dither + 1.0);

	bool hit = false;

    for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
        if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

        #ifdef REAL_SKY_REFLECTIONS
            if (rayPos.z >= 1.0) { hit = true; break; }
        #else
            if (rayPos.z >= 1.0) break;
        #endif

        float sampleDepth = readDepth1(ivec2(rayPos.xy));
		float diff = rayPos.z - sampleDepth;

        if (clamp(diff, 0.0, depthTolerance) == diff) {
            hit = true;
            break;
        }

        #ifdef RAYTRACE_ADAPTIVE_STEP
            rayStep = rayDir * max((sampleDepth - rayPos.z) * stepWeight, 1e-2 * rSteps);
        #endif
    }

    // Refine hit position (binary search)
    #ifdef RAYTRACE_REFINEMENT
	if (hit) {
        for (uint i = 0u; i < RAYTRACE_REFINEMENT_STEPS; ++i) {
            rayStep *= 0.5;

            float sampleDepth = readDepth1(ivec2(rayPos.xy));

            rayPos += rayStep * (step(rayPos.z, sampleDepth) * 2.0 - 1.0);
        }
    }
    #endif

    return hit;
}