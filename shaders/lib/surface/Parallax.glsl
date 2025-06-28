
uniform ivec2 atlasSize;

#define OffsetCoord(coord) (tileOffset + tileScale * fract(coord))

vec3 CalculateParallax(in vec3 tangentViewDir, in vec2 texSize, in float dither) {
    const float rSteps = 1.0 / float(PARALLAX_SAMPLES);
    vec3 stepSize = vec3(tangentViewDir.xy, -1.0) * rSteps;
    stepSize.xy *= PARALLAX_DEPTH / -tangentViewDir.z;
    stepSize *= 2.0 * rSteps * (dither + 0.5);

    uint refinementIndex = 0u;
    vec3 offsetCoord = vec3(tileBase, 1.0);

    for (uint i = 1u; i <= PARALLAX_SAMPLES; ++i) {
        offsetCoord += stepSize * float(i);
        float sampleHeight = texelFetch(normals, ivec2(OffsetCoord(offsetCoord.xy) * texSize), 0).a;

        #ifdef PARALLAX_REFINEMENT
            // Refine the parallax mapping (binary search)
            if (sampleHeight > offsetCoord.z) {
                if (refinementIndex >= PARALLAX_REFINEMENT_STEPS) break;
                offsetCoord -= stepSize * float(i);
                stepSize *= 0.5;
                ++refinementIndex;
            }
        #endif
    }

    return offsetCoord;
}

//================================================================================================//

#ifdef PARALLAX_SHADOW
    float CalculateParallaxShadow(in vec3 tangentLightDir, in vec3 offsetCoord, in vec2 texSize, in float dither) {
        float parallaxShadow = 1.0;

        const float rSteps = 1.0 / float(PARALLAX_SAMPLES);
        vec3 stepSize = vec3(tangentLightDir.xy, 1.0) * offsetCoord.z * rSteps;
        stepSize.xy *= PARALLAX_DEPTH / tangentLightDir.z;
        stepSize *= 2.0 * rSteps * (dither + 0.5);

        for (uint i = 1u; i <= PARALLAX_SAMPLES && parallaxShadow > 1e-3; ++i) {
            float sampleHeight = texelFetch(normals, ivec2(OffsetCoord(offsetCoord.xy) * texSize), 0).a;

            parallaxShadow *= step(sampleHeight, offsetCoord.z);
            offsetCoord += stepSize * float(i);
        }

        return 1.0 - parallaxShadow;
    }
#endif
