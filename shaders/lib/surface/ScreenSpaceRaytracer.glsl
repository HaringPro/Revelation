
#define RAYTRACE_SAMPLES 18 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define REAL_SKY_REFLECTIONS

#define RAYTRACE_REFINEMENT
#define RAYTRACE_REFINEMENT_STEPS 6 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

#define RAYTRACE_ADAPTIVE_STEP

//================================================================================================//

#if defined PASS_DEFERRED_LIGHTING
#define loadDepthMacro loadDepth0
#define loadDepthMacroDH loadDepth0DH
#else
#define loadDepthMacro loadDepth1
#define loadDepthMacroDH loadDepth1DH
#endif

#if !defined PASS_DH_WATER
bool ScreenSpaceRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in uint steps, inout vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return false;

    float rSteps = 1.0 / float(steps);

	float rayLength = 1e23 - (near + viewPos.z) / viewDir.z;

    vec3 endPos = ViewToScreenSpace(viewDir * rayLength + viewPos);
    vec3 rayDir = normalize(endPos - rayPos);
    float stepWeight = 1.0 / rayDir.z;

    float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rSteps;

    rayDir.xy *= viewSize;
    rayPos.xy *= viewSize;

    vec3 rayStep = rayDir * stepLength;
    rayPos += rayStep * (dither + 1.0);

	float diffTolerance = max(0.2 * oms(rayPos.z), -2.0 * rayStep.z);
    #if defined DISTANT_HORIZONS
        float screenDepthMax = ViewToScreenDepth(ScreenToViewDepthDH(1.0));
    #else
        #define screenDepthMax 1.0
    #endif

	bool hit = false;

    for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
        if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

        #ifdef REAL_SKY_REFLECTIONS
            if (rayPos.z >= screenDepthMax) { hit = true; break; }
        #else
            if (rayPos.z >= screenDepthMax) break;
        #endif

        float sampleDepth = loadDepthMacro(ivec2(rayPos.xy));
        #if defined DISTANT_HORIZONS
            if (sampleDepth > 0.999999) sampleDepth = ViewToScreenDepth(ScreenToViewDepthDH(loadDepthMacroDH(ivec2(rayPos.xy))));
        #endif

		float difference = rayPos.z - sampleDepth;

        if (clamp(difference, 0.0, diffTolerance) == difference) {
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

            float sampleDepth = loadDepthMacro(ivec2(rayPos.xy));
            #if defined DISTANT_HORIZONS
                if (sampleDepth > 0.999999) sampleDepth = ViewToScreenDepth(ScreenToViewDepthDH(loadDepthMacroDH(ivec2(rayPos.xy))));
            #endif

            rayPos += rayStep * (step(rayPos.z, sampleDepth) * 2.0 - 1.0);
        }
    }
    #endif

    return hit;
}
#else
bool ScreenSpaceRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in uint steps, inout vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return false;

    float rSteps = 1.0 / float(steps);

    vec3 endPos = ViewToScreenSpaceDH(viewDir + viewPos);
    vec3 rayDir = normalize(endPos - rayPos);
    float stepWeight = 1.0 / rayDir.z;

    float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rSteps;

    rayDir.xy *= viewSize;
    rayPos.xy *= viewSize;

    vec3 rayStep = rayDir * stepLength;
    rayPos += rayStep * (dither + 1.0);

	float diffTolerance = max(0.2 * oms(rayPos.z), -2.0 * rayStep.z);

	bool hit = false;

    for (uint i = 0u; i < steps; ++i, rayPos += rayStep) {
        if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

        #ifdef REAL_SKY_REFLECTIONS
            if (rayPos.z > 0.999999) { hit = true; break; }
        #else
            if (rayPos.z > 0.999999) break;
        #endif

        float sampleDepth = loadDepthMacroDH(ivec2(rayPos.xy));
		float difference = rayPos.z - sampleDepth;

        if (clamp(difference, 0.0, diffTolerance) == difference) {
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

            float sampleDepth = loadDepthMacroDH(ivec2(rayPos.xy));

            rayPos += rayStep * (step(rayPos.z, sampleDepth) * 2.0 - 1.0);
        }
    }
    #endif

    return hit;
}
#endif