
#define OffsetCoord(coord) (tileOffset + tileScale * fract(coord))

vec3 CalculateParallax(in vec3 tangentViewDir, in mat2 texGrad, in float dither) {
    vec3 offsetCoord = vec3(tileCoord, 1.0);

    const float rSteps = 1.0 / float(PARALLAX_SAMPLES);
    vec3 stepSize = vec3(tangentViewDir.xy, -1.0) * rSteps;
    stepSize.xy *= PARALLAX_DEPTH * rcp(-tangentViewDir.z);
    stepSize *= 2.0 * rSteps;

    uint refinementIndex = 0u;
    offsetCoord += stepSize * dither;
    for (uint i = 1u; i < PARALLAX_SAMPLES; ++i) {
        offsetCoord += stepSize * i;

        float sampleHeight = textureGrad(normals, OffsetCoord(offsetCoord.xy), texGrad[0], texGrad[1]).a;

        #ifdef PARALLAX_REFINEMENT
            if (sampleHeight > offsetCoord.z) {
                if (refinementIndex >= PARALLAX_REFINEMENT_STEPS) break;
                offsetCoord -= stepSize * i;
                stepSize *= 0.5;
                ++refinementIndex;
            }
        #endif
    }

    return offsetCoord;
}

#ifdef PARALLAX_SHADOW
    float CalculateParallaxShadow(in vec3 tangentLightVector, in vec3 offsetCoord, in mat2 texGrad, in float dither) {
        float parallaxShadow = 1.0;

        const float rSteps = 1.0 / float(PARALLAX_SAMPLES);
        vec3 stepSize = vec3(tangentLightVector.xy, 1.0) * offsetCoord.z * rSteps;
        stepSize.xy *= PARALLAX_DEPTH * rcp(tangentLightVector.z);
        stepSize *= 2.0 * rSteps;

        // uint refinementIndex = 0u;
        offsetCoord += stepSize * dither;
        for (uint i = 1u; i < PARALLAX_SAMPLES && parallaxShadow > 1e-3; ++i) {
            offsetCoord += stepSize * i;

            float sampleHeight = textureGrad(normals, OffsetCoord(offsetCoord.xy), texGrad[0], texGrad[1]).a;

            #if 0
                #ifdef PARALLAX_REFINEMENT
                    if (sampleHeight > offsetCoord.z) {
                        if (refinementIndex >= PARALLAX_REFINEMENT_STEPS) break;
                        offsetCoord -= stepSize * i;
                        stepSize *= 0.5;
                        ++refinementIndex;
                    }
                #endif
            #endif

            parallaxShadow *= step(sampleHeight, offsetCoord.z);
        }

        return 1.0 - parallaxShadow;
    }
#endif
