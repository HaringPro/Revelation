/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Accumulation and variance estimation
	Reference:  https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering://svgf_preprint.pdf
                https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

const bool colortex3MipmapEnabled = true;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 3,14 */
layout (location = 0) out vec4 indirectCurrent;
layout (location = 1) out vec2 varianceMoments;

//======// Uniform //=============================================================================//

writeonly restrict uniform image2D colorimg2;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

vec4 TemporalFilter(in ivec2 texel, in vec3 screenPos, in vec3 worldNormal, in float viewDistance) {
    vec2 prevCoord = Reproject(screenPos).xy;

    float luma = texelFetch(colortex3, texel, 0).r; // We use YCoCg color space
    ivec2 texelEnd = ivec2(halfViewEnd) - 1;

    // Estimate spatial variance
    vec2 currMoments = vec2(luma, luma * luma);
    #if 1
	    for (uint i = 0u; i < 8u; ++i) {
            ivec2 sampleTexel = clamp(texel + offset3x3N[i], ivec2(1), texelEnd);
            float sampleLuma = texelFetch(colortex3, sampleTexel, 0).r; // We use YCoCg color space

            currMoments += vec2(sampleLuma, sampleLuma * sampleLuma);
        }

        currMoments *= 1.0 / 9.0;
    #endif
    varianceMoments.xy = currMoments;

    if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
        vec4 prevDiffuse = vec4(0.0);
        vec2 prevMoments = vec2(0.0);
        float sumWeight = 0.0;
        float confidence = 0.0;

        prevCoord += (prevTaaOffset - taaOffset) * 0.25;

        // Custom bilinear filter
        vec2 prevTexel = prevCoord * 0.5 * viewSize - vec2(0.5);
        ivec2 floorTexel = ivec2(floor(prevTexel));
        vec2 fractTexel = prevTexel - vec2(floorTexel);

        float bilinearWeight[4] = {
            oms(fractTexel.x) * oms(fractTexel.y),
            fractTexel.x      * oms(fractTexel.y),
            oms(fractTexel.x) * fractTexel.y,
            fractTexel.x      * fractTexel.y
        };

        ivec2 offsetToBR = ivec2(halfViewSize.x, 0);
		float depthPhi = -8.0 / viewDistance;

        for (uint i = 0u; i < 4u; ++i) {
            ivec2 sampleTexel = floorTexel + offset2x2[i];
            if (clamp(sampleTexel, ivec2(1), texelEnd) == sampleTexel) {
                vec3 sampleAux = texelFetch(colortex2, sampleTexel + offsetToBR, 0).rgb;

                float weight = pow8(saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal)));
                weight *= exp2(abs(viewDistance - sampleAux.z) * depthPhi);
                confidence = max(confidence, weight);
                weight *= bilinearWeight[i];

                prevDiffuse += texelFetch(colortex2, sampleTexel, 0) * weight;
                prevMoments += texelFetch(colortex14, sampleTexel, 0).xy * weight;
                sumWeight += weight;
            }
        }

        if (sumWeight > EPS) {
            sumWeight = 1.0 / sumWeight;
            prevDiffuse *= sumWeight;
            prevMoments *= sumWeight;

            float sampleIndex = min(prevDiffuse.a * confidence + 1.0, SSILVB_MAX_ACCUM_FRAMES);
            float alpha = rcp(sampleIndex);

            // See section 4.2 of the paper
            // if (sampleIndex > 4.5) {
                varianceMoments.xy = mix(prevMoments, varianceMoments.xy, alpha);
            // }

            float mipLevel = 3.0 * saturate(1.0 - sampleIndex * rcp(16.0));
            indirectCurrent.rgb = textureLod(colortex3, screenPos.xy * 0.5, mipLevel).rgb;
            indirectCurrent.rgb = mix(prevDiffuse.rgb, indirectCurrent.rgb, alpha);

            indirectCurrent.a = max0(varianceMoments.y - varianceMoments.x * varianceMoments.x);

            return vec4(indirectCurrent.rgb, sampleIndex);
        }
    }

    indirectCurrent.rgb = textureLod(colortex3, screenPos.xy * 0.5, 3.0).rgb;
    indirectCurrent.a = sqr(varianceMoments.x);

    return vec4(0.0);
}

float SampleDepthMin4x4(in sampler2D depthTex, in vec2 coord) {
	// 4x4 pixel neighborhood using textureGatherOffset
	float LL = minOf(textureGatherOffset(depthTex, coord, ivec2(-2, -2)));
	float LR = minOf(textureGatherOffset(depthTex, coord, ivec2(-2,  2)));
	float UL = minOf(textureGatherOffset(depthTex, coord, ivec2( 2, -2)));
	float UR = minOf(textureGatherOffset(depthTex, coord, ivec2( 2,  2)));

	return min(min(LL, LR), min(UL, UR));
}

//======// Main //================================================================================//
void main() {
    vec2 currentCoord = gl_FragCoord.xy * viewPixelSize * 2.0;

    indirectCurrent = vec4(0.0);
    varianceMoments = vec2(0.0);

    if (saturate(currentCoord) == currentCoord) {
        ivec2 screenTexel = ivec2(gl_FragCoord.xy);

        ivec2 currentTexel = screenTexel << 1;
        float depth = SampleDepthMin4x4(depthtex0, currentCoord);
        #if defined LOD_MOD
            bool lodTerrainMask = depth > (1.0 - EPS);
            if (lodTerrainMask) depth = loadDepthTransLod(currentTexel);
        #endif

        if (depth < 1.0) {
            #if defined DISTANT_HORIZONS
                if (dhTerrainMask) depth = ViewToScreenDepth(ScreenToViewDepthDH(depth));
            #endif

            vec3 screenPos = vec3(currentCoord, depth);
            vec3 viewPos = ScreenToViewSpace(screenPos);
            float viewDistance = length(viewPos);

            vec3 worldNormal = FetchSurfaceNormal(currentTexel);
            vec4 indirectHistory = TemporalFilter(screenTexel, screenPos, worldNormal, viewDistance);

            // Vanilla lightmap blending
            float blocklight = Unpack2x8UX(loadMaterialPack(currentTexel).x);
            blocklight = pow5(blocklight) * exp2(-16.0 * indirectCurrent.x * global.exposure.value);
            indirectCurrent.rgb += sRGBToYCoCg(blackbody(float(BLOCKLIGHT_TEMPERATURE))) * saturate(blocklight) * SSILVB_BLENDED_LIGHTMAP;

            imageStore(colorimg2, screenTexel, indirectHistory);
            imageStore(colorimg2, screenTexel + ivec2(halfViewSize.x, 0), vec4(OctEncodeSnorm(worldNormal), viewDistance, 1.0));
        }
    }
}