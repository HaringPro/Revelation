/*
--------------------------------------------------------------------------------

	Revoxelation Shaders

	Copyright (C) 2024 HaringPro
	All Rights Reserved

    Pass: Accumulation for indirect diffuse irradiance and variance estimation
	Reference:  https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering://svgf_preprint.pdf
                https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,3,14 */
layout (location = 0) out vec4 frameIndex;
layout (location = 1) out vec4 diffuseCurrent;
layout (location = 2) out vec4 varianceMoments;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"
#include "/lib/universal/Offset.glsl"

void TemporalFilter(in ivec2 screenTexel, in vec2 prevCoord, in vec3 worldNormal) {
    diffuseCurrent.rgb = texelFetch(colortex3, screenTexel/*  >> 1 */, 0).rgb;
    float luminance = luminance(diffuseCurrent.rgb);

    // Estimate spatial variance
    vec2 currMoments = vec2(luminance, luminance * luminance);
    {
        float sumWeight = 1.0;

        ivec2 texelEnd = ivec2(viewSize) - 1;

        for (int x = -1; x <= 1; ++x) {
            for (int y = -1; y <= 1; ++y) {
                if (x == 0 && y == 0) continue;

                ivec2 sampleTexel = clamp(screenTexel + ivec2(x, y)/*  * 2 */, ivec2(0), texelEnd);
                vec3 sampleColor = texelFetch(colortex3, sampleTexel/*  >> 1 */, 0).rgb;
                float sampleLuma = luminance(sampleColor);

                vec3 sampleNormal = FetchWorldNormal(loadGbufferData0(sampleTexel));
                float weight = saturate(dot(sampleNormal, worldNormal) * 20.0 - 19.0);

                currMoments += vec2(sampleLuma, sampleLuma * sampleLuma) * weight;
                diffuseCurrent.rgb += sampleColor * weight;
                sumWeight += weight;
            }
        }

        sumWeight = 1.0 / sumWeight;
        currMoments *= sumWeight;
        diffuseCurrent.rgb *= sumWeight;
    }
    varianceMoments.xy = currMoments;

    if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
        vec4 prevDiffuse = vec4(0.0);
        vec2 prevMoments = vec2(0.0);
        float sumWeight = 0.0;

        prevCoord += (prevTaaOffset - taaOffset) * 0.125;

        // Custom bilinear filter
        vec2 prevTexel = prevCoord * viewSize - vec2(0.5);
        ivec2 floorTexel = ivec2(floor(prevTexel));
        vec2 fractTexel = prevTexel - vec2(floorTexel);

        float bilinearWeight[4] = {
            oms(fractTexel.x) * oms(fractTexel.y),
            fractTexel.x           * oms(fractTexel.y),
            oms(fractTexel.x) * fractTexel.y,
            fractTexel.x           * fractTexel.y
        };

        ivec2 texelEnd = ivec2(viewSize) - 1;

        for (uint i = 0u; i < 4u; ++i) {
            ivec2 sampleTexel = floorTexel + offset2x2[i];
            if (clamp(sampleTexel, ivec2(0), texelEnd) == sampleTexel) {
			    vec4 sampleData = texelFetch(colortex14, sampleTexel, 0);
                #define prevLinerDepth sampleData.w

                if (abs((varianceMoments.w - prevLinerDepth) - cameraMovement.z) < 0.1 * abs(varianceMoments.w)) {
                    vec3 prevWorldNormal = FetchWorldNormal(sampleData.z);
                    float weight = bilinearWeight[i] * saturate(dot(prevWorldNormal, worldNormal) * 8.0 - 7.0);

                    prevDiffuse += texelFetch(colortex2, sampleTexel, 0) * weight;
                    prevMoments += sampleData.xy * weight;
                    sumWeight += weight;
                }
            }
        }

        if (sumWeight > 1e-6) {
            sumWeight = 1.0 / sumWeight;
            prevDiffuse *= sumWeight;
            prevMoments *= sumWeight;

            frameIndex.a = min(prevDiffuse.a + 1.0, PT_DIFFUSE_MAX_ACCUM_FRAMES);
            float alpha = rcp(frameIndex.a);
            // float alphaDiffuse = alpha;

            // Checkerboard upscaling
            // ivec2 checkerboard = checkerboardOffset2x2[frameCounter % 4];
            // if (screenTexel % 2 != checkerboard) alphaDiffuse *= 0.5;
            // screenTexel -= checkerboard;
            // screenTexel >>= 1;

            // See section 4.2 of the paper
            if (frameIndex.a > 4.5) {
                varianceMoments.xy = mix(prevMoments, varianceMoments.xy, alpha);
            }

            diffuseCurrent.rgb = mix(prevDiffuse.rgb, diffuseCurrent.rgb, alpha);
        }
    }

    diffuseCurrent.a = varianceMoments.x * varianceMoments.x;
    diffuseCurrent.a = max0(varianceMoments.y - diffuseCurrent.a) + (diffuseCurrent.a + 0.1) * (32.0 / frameIndex.a);
    diffuseCurrent.a *= 64.0;
    // diffuseCurrent.a *= inversesqrt(diffuseCurrent.a + 1e-6);
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    float depth = loadDepth0(screenTexel);

    diffuseCurrent = frameIndex = vec4(vec3(0.0), 1.0);
    varianceMoments = vec4(0.0);

    varianceMoments.w = ScreenToViewDepth(depth);

    if (depth < 1.0) {
        #if defined NORMAL_MAPPING
            uint data = loadGbufferData0(screenTexel).w;
        #else
            uint data = loadGbufferData0(screenTexel).z;
        #endif
        vec2 encodedNormal = Unpack2x8U(data);
        vec3 worldNormal = decodeUnitVector(encodedNormal);

        varianceMoments.z = Packup2x8F(encodedNormal);

        vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, depth);
        vec2 prevCoord = Reproject(screenPos).xy;
        TemporalFilter(screenTexel, prevCoord, worldNormal);
    }
}