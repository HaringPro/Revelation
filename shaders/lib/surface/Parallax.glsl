
// uniform ivec2 atlasSize;
/*
float BilinearHeightSample(in vec2 coord)
{
    ivec2 tileOffset = ivec2(tileOffset * tileScale);
    coord = coord * atlasSize - 0.5;
    ivec2 i = ivec2(coord);

    vec4 sh = vec4(
        texelFetch(normals, (i + ivec2(0, 1)) % atlasSize + tileOffset, 0).a,
        texelFetch(normals, (i + ivec2(1, 1)) % atlasSize + tileOffset, 0).a,
        texelFetch(normals, (i + ivec2(1, 0)) % atlasSize + tileOffset, 0).a,
        texelFetch(normals, (i + ivec2(0, 0)) % atlasSize + tileOffset, 0).a
    );

    sh += step(sh, vec4(1e-3));
    vec2 fpc = fract(coord);

    sh.xy = mix(sh.wx, sh.zy, fpc.x);
    return mix(sh.x, sh.y, fpc.y);
}
*/
vec3 CalculateParallax(in vec3 tangentViewDir, in mat2 texGrad, in float dither) {
    vec3 offsetCoord = vec3(tileCoord, 1.0);
    vec3 stepSize = vec3(tangentViewDir.xy, -1.0) * rcp(PARALLAX_SAMPLES);
    stepSize.xy *= PARALLAX_DEPTH * rcp(-tangentViewDir.z);
    stepSize *= 2.0 / PARALLAX_SAMPLES;

    uint currRefinements = 0u;
    offsetCoord += stepSize * dither;
    for (uint i = 1u; i < PARALLAX_SAMPLES; ++i) {
        offsetCoord += stepSize * i;

        #ifdef SMOOTH_PARALLAX
            float sampleHeight = BilinearHeightSample(OffsetCoord(offsetCoord.xy));
        #else
            float sampleHeight = textureGrad(normals, OffsetCoord(offsetCoord.xy), texGrad[0], texGrad[1]).a;
        #endif

        #ifdef PARALLAX_REFINEMENT
            if (sampleHeight > offsetCoord.z) {
                if (currRefinements >= PARALLAX_REFINEMENT_STEPS) break;
                offsetCoord -= stepSize * i;
                stepSize *= 0.5;
                ++currRefinements;
            }
        #endif
    }

    return offsetCoord;
}
#ifdef PARALLAX_SHADOW
    float CalculateParallaxShadow(in vec3 tangentLightVector, in vec3 offsetCoord, in mat2 texGrad, in float dither) {
        float parallaxShadow = 1.0;
        //vec3 offsetCoord = vec3(parallaxCoord, parallaxDepth);

        vec3 stepSize = vec3(tangentLightVector.xy, 1.0) * offsetCoord.z * rcp(PARALLAX_SAMPLES);
        stepSize.xy *= PARALLAX_DEPTH * rcp(tangentLightVector.z);
        stepSize *= 2.0 / PARALLAX_SAMPLES;

        //int currRefinements = 0;
        offsetCoord += stepSize * dither;
        for (uint i = 1u; i < PARALLAX_SAMPLES; ++i) {
            offsetCoord += stepSize * i;
            //vec2 sampleCoord = OffsetCoord(offsetCoord.xy);

            #ifdef SMOOTH_PARALLAX
                float sampleHeight = BilinearHeightSample(OffsetCoord(offsetCoord.xy));
            #else
                float sampleHeight = textureGrad(normals, OffsetCoord(offsetCoord.xy), texGrad[0], texGrad[1]).a;
            #endif
        /*
            #ifdef PARALLAX_REFINEMENT
                if (sampleHeight > offsetCoord.z) {
                    if (currRefinements < PARALLAX_REFINEMENT_STEPS) {
                        offsetCoord -= stepSize * i;
                        stepSize *= 0.5;
                        currRefinements++;
                    }else{
                        break;
                    }
                }
            #endif
        */
            parallaxShadow *= float(offsetCoord.z > sampleHeight);
            if (parallaxShadow < 1e-4) break;
        }

        return 1.0 - parallaxShadow;
    }
#endif
