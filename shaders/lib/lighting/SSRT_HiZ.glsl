// Reference:
// Yasin Uludag, "Hi-Z Screen-Space Cone-Traced Reflection". GPU Pro 5, 2014.

#if !defined INCLUDE_LIGHTING_SSRT_HIZ
#define INCLUDE_LIGHTING_SSRT_HIZ

// 2-level Hi-Z: level 0 = half-res min-depth, level 1 = full-res depth check
#define HIZ_MAX_LEVEL 1

float SampleHiZ(ivec2 texel) {
    return texelFetch(colortex5, texel >> 1, 0).r;
}

bool HiZRaytrace(vec3 viewOrigin, vec3 viewDir, float dither, uint steps, inout vec3 hitPos) {
    float maxDist = step(viewDir.z, 0.0) * 1e23 - (viewOrigin.z + near) / viewDir.z;
    vec3 rayEnd = viewOrigin + viewDir * maxDist;

    vec3 rayOrigin = ViewToScreenPos(viewOrigin);
    vec3 rayDir = ViewToScreenPos(rayEnd) - rayOrigin;
    float totalDist = length(rayDir.xy);
    rayDir /= max(totalDist, 1e-6);

    float rSteps = 1.0 / float(steps);
    vec3 rayStep = rayDir * rSteps;
    float invDirZ = rcp(max(abs(rayStep.z), 1e-6));

    float compareTolerance = 2.0 * max(abs(rayStep.z), (rayOrigin.z + gbufferProjection[2].z) * rSteps);

    float t = dither;
    bool hit = false;

    for (uint i = 0u; i < steps; ++i) {
        hitPos = rayOrigin + rayStep * t;

        if (saturate(hitPos.xy) != hitPos.xy) break;

        // Coarse check: skip entire 2x2 block if ray is in front
        ivec2 coarseTexel = ivec2(hitPos.xy * vec2(viewWidth, viewHeight) * 0.5);
        float minDepth = SampleHiZ(coarseTexel);

        if (hitPos.z < minDepth - 0.001) {
            // Ray is in front of the entire 2x2 block, skip ahead
            float skipAmount = (minDepth - hitPos.z) * invDirZ * 0.5;
            t += max(skipAmount, 0.01);
            continue;
        }

        // Fine check: test against actual depth
        ivec2 sampleTexel = uvToTexelScaled(hitPos.xy);
        float sampleDepth = loadDepth2(sampleTexel);

        float depthDiff = sampleDepth - hitPos.z;
        if (abs(depthDiff + compareTolerance) < compareTolerance) {
            hit = true;
            break;
        }

        t += clamp(depthDiff * invDirZ, 0.01, 1.1);
    }

#ifdef SSRT_REFINEMENT
    if (hit) {
        for (uint i = 0u; i < SSRT_REFINEMENT_STEPS; ++i) {
            rayStep *= 0.5;
            ivec2 sampleTexel = uvToTexelScaled(hitPos.xy);
            float sampleDepth = loadDepth2(sampleTexel);
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

#endif