
#define RAYTRACE_SAMPLES 16 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define REAL_SKY_REFLECTIONS

#define RAYTRACE_REFINEMENT
#define RAYTRACE_REFINEMENT_STEPS 6 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

bool ScreenSpaceRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, const in uint steps, inout vec3 rayPos) {
    const float rSteps = 1.0 / float(steps);

    vec3 position = ViewToScreenSpace(viewDir * abs(viewPos.z) + viewPos);
    vec3 screenDir = normalize(position - rayPos);
    float stepWeight = 1.0 / screenDir.z;

    float stepLength = minOf((step(0.0, screenDir) - rayPos) / screenDir) * rSteps;
    float minLength = stepLength * 1e-2;

    screenDir.xy *= viewSize;
    rayPos.xy *= viewSize;

    vec3 rayStep = screenDir * stepLength;
    rayPos += rayStep * (dither + 1.0);

	bool hit = false;

    #ifdef RAYTRACE_REFINEMENT
        uint refinementSamp = 0u;
    #endif

	float depthTolerance = max(exp2(1e-2 * viewPos.z - 8.0), -rayStep.z);

    for (uint i = 0u; i < steps; ++i) {
        if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

        #ifdef REAL_SKY_REFLECTIONS
            if (rayPos.z >= 1.0) { hit = true; break; }
        #else
            if (rayPos.z >= 1.0) break;
        #endif

        float sampleDepth = sampleDepthSoild(ivec2(rayPos.xy));

        rayStep = screenDir * clamp((sampleDepth - rayPos.z) * stepWeight, minLength, rSteps);
        rayPos += rayStep;

        if (sampleDepth < rayPos.z) {
            #ifdef RAYTRACE_REFINEMENT
                if (refinementSamp < RAYTRACE_REFINEMENT_STEPS) {
                    ++refinementSamp;
                    rayStep *= 0.5;

                    rayPos += rayStep * (step(rayPos.z, sampleDepth) * 2.0 - 1.0);

                    sampleDepth = sampleDepthSoild(ivec2(rayPos.xy));
                }
            #endif
            // float sampleDepthLinear = GetDepthLinear(sampleDepth);
            // float traceDepthLinear = GetDepthLinear(rayPos.z);
            if (rayPos.z - sampleDepth < depthTolerance) {
                hit = true;
                break;
            }
        }
    }

    return hit;
}
