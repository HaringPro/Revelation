// Reference:
// Morgan McGuire, Michael Mara. "Efficient GPU Screen-Space Ray Tracing". JCGT, 2014.
// https://jcgt.org/published/0003/04/04/paper.pdf

#define SSRT_MAX_SAMPLES 16 // [4 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define SSRT_SKY_TRACING

#define SSRT_REFINEMENT
#define SSRT_REFINEMENT_STEPS 4 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

//================================================================================================//

bool ScreenSpaceRaytrace(vec3 viewPos, vec3 viewDir, float dither, uint steps, inout vec3 screenPos) {
    vec3 origin = screenPos;

    float fixZ = step(viewDir.z, 0.0) * 1e23 - (viewPos.z + near) / viewDir.z;
    vec3 rayDir = normalize(ViewToScreenPos(viewDir * fixZ + viewPos) - origin);
    rayDir *= minOf((step(0.0, rayDir) - screenPos) / rayDir);

    rayDir.xy *= viewSize;
    origin.xy *= viewSize;

    float rSteps = 1.0 / float(steps);
    float invDirZ = rcp(abs(rayDir.z));
    vec3 rayStep = rayDir * rSteps;

    #if defined LOD_MOD
        float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
    #else
        #define screenDepthSky 1.0
    #endif

	bool hit = false;

    float t = dither * rSteps;
    for (uint i = 0u; i < steps; ++i) {
        vec3 rayPos = origin + rayDir * t;

        if (clamp(rayPos.xy, vec2(0.0), viewSize - 1.0) != rayPos.xy) break;
        if (rayPos.z >= screenDepthSky) {
        #ifdef SSRT_SKY_TRACING
            screenPos = rayPos;
            hit = true;
        #endif
            break;
        }

        float sampleDepth = loadDepth2(ivec2(rayPos.xy));
        #if defined LOD_MOD
            if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(ivec2(rayPos.xy))));
        #endif

		if (rayPos.z > sampleDepth) {
            float sampleViewZ = ScreenToViewDepth(sampleDepth);
            float stepViewZ = ScreenToViewDepth(rayPos.z);

            if (distance(sampleViewZ, stepViewZ) < -0.1 * stepViewZ) {
                screenPos = rayPos;
                hit = true;
                break;
            }
        }

        t += clamp((sampleDepth - rayPos.z) * invDirZ, rSteps * 0.01, rSteps * 1.1);
    }

    #ifdef SSRT_REFINEMENT
    if (hit) {
        // Refine hit position (binary search)
        for (uint i = 0u; i < SSRT_REFINEMENT_STEPS; ++i) {
            rayStep *= 0.5;

            float sampleDepth = loadDepth2(ivec2(screenPos.xy));
            #if defined LOD_MOD
                if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(ivec2(screenPos.xy))));
            #endif

            screenPos += signMul(rayStep, sampleDepth - screenPos.z);
        }
    }
    #endif

    screenPos.xy *= viewPixelSize;

    return hit;
}