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

vec4 TemporalFilter(in ivec2 texel, in vec3 screenPos, in vec3 worldNormal, out float viewDistance) {
	vec3 viewPos = ScreenToViewSpaceRaw(screenPos);
    vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
    viewDistance = sdot(worldPos);

    float distInv = inversesqrt(viewDistance);
    vec3 worldDir = worldPos * distInv;
    viewDistance *= distInv;

	worldPos += cameraMovement * step(0.56, screenPos.z); // To previous frame's world space
    worldPos = transMAD(gbufferPreviousModelView, worldPos); // To previous frame's view space
	worldPos = projMAD(gbufferPreviousProjection, worldPos) * rcp(-worldPos.z); // To previous frame's NDC space

    vec2 prevCoord = worldPos.xy * 0.5 + 0.5;

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

        ivec2 tileOffset = ivec2(halfViewSize.x, 0);
		float NdotV = abs(dot(worldNormal, worldDir));

        for (uint i = 0u; i < 4u; ++i) {
            ivec2 sampleTexel = floorTexel + offset2x2[i];
            if (clamp(sampleTexel, ivec2(1), texelEnd) == sampleTexel) {
                vec3 sampleAux = texelFetch(colortex2, sampleTexel + tileOffset, 0).rgb;

                vec4 sampleDiffuse = texelFetch(colortex2, sampleTexel, 0);

                float weight = -abs(viewDistance - sampleAux.z) * NdotV;
                weight += log2(saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal)));
                weight = exp2(weight * sampleDiffuse.a * (8.0 / SSILVB_MAX_ACCUM_FRAMES));

                confidence = max(confidence, weight);
                weight *= bilinearWeight[i];

                prevDiffuse += sampleDiffuse * weight;
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

            float mipLevel = 3.0 * saturate(1.0 - sampleIndex * rcp(12.0));
            indirectCurrent.rgb = textureLod(colortex3, screenPos.xy * 0.5, mipLevel).rgb;
            indirectCurrent.rgb = mix(prevDiffuse.rgb, indirectCurrent.rgb, alpha);

            indirectCurrent.a = max0(varianceMoments.y - varianceMoments.x * varianceMoments.x);

            return vec4(indirectCurrent.rgb, sampleIndex);
        }
    }

    indirectCurrent.rgb = textureLod(colortex3, screenPos.xy * 0.5, 3.0).rgb;
    indirectCurrent.a = sqr(varianceMoments.x);

    return vec4(indirectCurrent.rgb, 1.0);
}

float GetClosestDepthN(in ivec2 texel) {
    float depth = 1.0;

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = offset3x3N[i] + texel;
        float sampleDepth = loadDepth0(sampleTexel);
        depth = min(depth, sampleDepth);
    }

    return depth;
}

//======// Main //================================================================================//
void main() {
    vec2 renderCoord = gl_FragCoord.xy * viewPixelSize * 2.0;

    indirectCurrent = vec4(0.0);
    varianceMoments = vec2(0.0);

    if (saturate(renderCoord) == renderCoord) {
        ivec2 texelPos = ivec2(gl_FragCoord.xy);

        ivec2 renderTexel = texelPos << 1;

        float depth = loadDepth0(renderTexel);
        bool terrainCheck = min(GetClosestDepthN(renderTexel), depth) < 1.0;
        #if defined LOD_MOD
            bool lodTerrainMask = !terrainCheck;
            if (lodTerrainMask) {
                depth = loadDepth0Lod(renderTexel);
                terrainCheck = depth < 1.0;
            }
        #endif

        if (terrainCheck) {
            #if defined LOD_MOD
			    if (lodTerrainMask) depth = ViewToScreenDepth(ScreenToViewDepthLod(depth));
            #endif

            vec3 screenPos = vec3(renderCoord, depth);
            vec3 worldNormal = FetchSurfaceNormal(renderTexel);

            float viewDistance;
            vec4 indirectHistory = TemporalFilter(texelPos, screenPos, worldNormal, viewDistance);

            // Vanilla lightmap blending
            float blocklight = Unpack2x8UX(loadMaterialPack(renderTexel).x);
            blocklight = pow5(blocklight) * exp2(-16.0 * indirectCurrent.x * global.exposure.value);
            indirectCurrent.rgb += sRGBToYCoCg(blackbody(float(BLOCKLIGHT_TEMPERATURE))) * saturate(blocklight) * SSILVB_BLENDED_LIGHTMAP;

            imageStore(colorimg2, texelPos, indirectHistory);
            imageStore(colorimg2, texelPos + ivec2(halfViewSize.x, 0), vec4(OctEncodeSnorm(worldNormal), viewDistance, 1.0));
        }
    }
}