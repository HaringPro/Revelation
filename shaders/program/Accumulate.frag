/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Accumulation for indirect lighting and variance estimation
	Reference:  https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering://svgf_preprint.pdf
                https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define SSPT_MAX_BLENDED_FRAMES 160.0 // [20.0 24.0 28.0 32.0 36.0 40.0 48.0 56.0 64.0 72.0 80.0 96.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 448.0 512.0 640.0 768.0 896.0 1024.0]

#define SSPT_SAMPLER colortex3
#define SSPT_VARIANCE_SCALE 0.02

//======// Output //==============================================================================//

/* RENDERTARGETS: 3,13,14 */
layout (location = 0) out vec4 indirectCurrent;
layout (location = 1) out vec4 indirectHistory;
layout (location = 2) out vec3 historyBuffer; // xy: moments history, z: inverse depth

//======// Uniform //=============================================================================//

#include "/lib/utility/Uniform.glsl"

uniform sampler2D colortex13; // Previous indirect light
uniform sampler2D colortex14; // Previous moments

uniform vec2 prevTaaOffset;

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"
#include "/lib/utility/Offset.glsl"

// #if AO_ENABLED > 0
// 	#include "/lib/lighting/AmbientOcclusion.glsl"
// #endif

float EstimateSpatialVariance(in ivec2 texel, in float luma) {
    const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};

    float sqLuma = luma * luma;
    luma *= kernel[0][0], sqLuma *= kernel[0][0];

    ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sampleCoord = texel + ivec2(x, y) * 2;
            if (clamp(sampleCoord, ivec2(0), maxLimit) == sampleCoord) {
                float weight = kernel[abs(x)][abs(y)];
                float sampleLuma = GetLuminance(texelFetch(SSPT_SAMPLER, sampleCoord, 0).rgb);

                luma   += sampleLuma * weight;
                sqLuma += sampleLuma * sampleLuma * weight;
            }
        }
    }
    return abs(sqLuma - luma * luma);
}

vec4 SpatialColor(in ivec2 texel) {
    const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};

    vec3 indirectData = texelFetch(SSPT_SAMPLER, texel, 0).rgb;

    float luma = GetLuminance(indirectData), sqLuma = luma * luma;
    indirectData *= kernel[0][0];
    luma *= kernel[0][0], sqLuma *= kernel[0][0];

    ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sampleCoord = texel + ivec2(x, y) * 2;
            if (clamp(sampleCoord, ivec2(0), maxLimit) == sampleCoord) {
                vec3 currentColor = texelFetch(SSPT_SAMPLER, sampleCoord, 0).rgb;

                float weight = kernel[abs(x)][abs(y)];
                float sampleLuma = GetLuminance(currentColor);

                indirectData += currentColor * weight;
                luma   += sampleLuma * weight;
                sqLuma += sampleLuma * sampleLuma * weight;
            }
        }
    }

    historyBuffer.xy = vec2(luma, sqLuma);
    return vec4(indirectData, abs(sqLuma - luma * luma));
}

vec3 SpatialCurrent(in ivec2 texel) {
    const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};

    vec3 indirectData = texelFetch(SSPT_SAMPLER, texel, 0).rgb;
    indirectData *= kernel[0][0];

    ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sampleCoord = texel + ivec2(x, y);
            if (clamp(sampleCoord, ivec2(0), maxLimit) == sampleCoord) {
                vec3 currentColor = texelFetch(SSPT_SAMPLER, sampleCoord, 0).rgb;

                float weight = kernel[abs(x)][abs(y)];
                float sampleLuma = GetLuminance(currentColor);

                indirectData += currentColor * weight;
            }
        }
    }
    return indirectData;
}

void TemporalFilter(in ivec2 screenTexel, in vec2 prevCoord, in vec3 viewPos) {
    vec4 prevLight = vec4(0.0);
    vec2 prevMoments = vec2(0.0);
    float sumWeight = 0.0;

    float cameraMovement = length(mat3(gbufferModelView) * (cameraPosition - previousCameraPosition));
    float currViewDistance = length(viewPos);

    prevCoord += (prevTaaOffset - taaOffset) * 0.125;

    // Bilinear filter
    vec2 prevTexel = prevCoord * viewSize - vec2(0.5);
    ivec2 floorTexel = ivec2(floor(prevTexel));
    vec2 fractTexel = fract(prevTexel - floorTexel);

    float weight[4] = {
        oneMinus(fractTexel.x) * oneMinus(fractTexel.y),
        fractTexel.x           * oneMinus(fractTexel.y),
        oneMinus(fractTexel.x) * fractTexel.y,
        fractTexel.x           * fractTexel.y
    };

    ivec2 shift = ivec2(viewWidth * 0.5, 0);
    ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

    for (uint i = 0u; i < 4u; ++i) {
        ivec2 sampleTexel = floorTexel + offset2x2[i];
        if (clamp(sampleTexel, ivec2(0), maxLimit) == sampleTexel) {
            vec4 prevData = texelFetch(colortex13, sampleTexel + shift, 0);

            if ((abs(currViewDistance - prevData.w) - cameraMovement) < 0.1 * currViewDistance) {
                float weight = weight[i];

                prevLight += texelFetch(colortex13, sampleTexel, 0) * weight;
                prevMoments += texelFetch(colortex14, sampleTexel, 0).xy * weight;
                sumWeight += weight;
            }
        }
    }

    if (sumWeight > 1e-5) {
        prevLight /= sumWeight;
        prevMoments /= sumWeight;

        // indirectCurrent.rgb = SpatialCurrent(screenTexel);
        indirectCurrent.rgb = texelFetch(SSPT_SAMPLER, screenTexel, 0).rgb;
        // indirectCurrent.rgb = textureSmoothFilter(SSPT_SAMPLER, gl_FragCoord.xy * viewPixelSize).rgb;

        indirectHistory.a = min(++prevLight.a, SSPT_MAX_BLENDED_FRAMES);
        float alpha = rcp(indirectHistory.a + 1.0);

        indirectCurrent.rgb = indirectHistory.rgb = mix(prevLight.rgb, indirectCurrent.rgb, alpha);

        float luminance = GetLuminance(indirectCurrent.rgb);

        vec2 currMoments = vec2(luminance, luminance * luminance);
        historyBuffer.xy = mix(prevMoments, currMoments, alpha);

        // See section 4.2 of the paper
        if (indirectHistory.a < 4.0) {
            indirectCurrent.a = EstimateSpatialVariance(screenTexel, luminance);
        } else {
            indirectCurrent.a = abs(historyBuffer.xy.y - historyBuffer.xy.x * historyBuffer.xy.x);
        }
    } else {
        indirectCurrent = SpatialColor(screenTexel);
        indirectHistory.rgb = indirectCurrent.rgb;
    }
}

float sampleDepthMin4x4(in vec2 coord) {
	// 4x4 pixel neighborhood using textureGather
    vec4 sampleDepth0 = textureGather(depthtex0, coord + vec2( 2.0,  2.0) * viewPixelSize);
    vec4 sampleDepth1 = textureGather(depthtex0, coord + vec2(-2.0,  2.0) * viewPixelSize);
    vec4 sampleDepth2 = textureGather(depthtex0, coord + vec2( 2.0, -2.0) * viewPixelSize);
    vec4 sampleDepth3 = textureGather(depthtex0, coord + vec2(-2.0, -2.0) * viewPixelSize);

    return min(min(minOf(sampleDepth0), minOf(sampleDepth1)), min(minOf(sampleDepth2), minOf(sampleDepth3)));
}

float GetClosestDepth(in ivec2 texel) {
    float depth = sampleDepth(texel);

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = offset3x3N[i] * 2 + texel;
        float sampleDepth = texelFetch(depthtex0, sampleTexel, 0).x;
        depth = min(depth, sampleDepth);
    }

    return depth;
}

//======// Main //================================================================================//
void main() {
    vec2 currentCoord = gl_FragCoord.xy * viewPixelSize * 2.0;
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);
    #if defined CLOUDS_ENABLED && defined CTU_ENABLED
        historyBuffer.z = 1.0 - sampleDepth(screenTexel);
    #endif

    if (currentCoord.y < 1.0) {
        if (currentCoord.x < 1.0) {
            // vec3 closestFragment = GetClosestFragment(currentTexel, depth);
            float depth = sampleDepthMin4x4(currentCoord);

            indirectCurrent = vec4(vec3(0.0), 1.0);
            indirectHistory = indirectCurrent;

            historyBuffer.xy = vec2(0.0);

            if (depth < 1.0) {
                ivec2 currentTexel = screenTexel * 2;
                // currentTexel = ivec2(closestFragment.xy * viewSize);
                vec3 worldNormal = FetchWorldNormal(sampleGbufferData0(currentTexel));

                vec3 screenPos = vec3(currentCoord, depth);
                vec3 viewPos = ScreenToViewSpace(screenPos);

                // #if AO_ENABLED == 1
                //     float dither = BlueNoiseTemporal(currentTexel);
                //     if (depth > 0.56) indirectCurrent.a = CalculateSSAO(screenPos.xy, viewPos, mat3(gbufferModelView) * worldNormal, dither);
                // #endif

                vec2 prevCoord = Reproject(screenPos).xy;
                if (saturate(prevCoord) != prevCoord || worldTimeChanged || depth < 0.56) {
                    indirectCurrent = SpatialColor(screenTexel);
                    indirectHistory.rgb = indirectCurrent.rgb;
                } else {
                    prevCoord *= 0.5;
                    TemporalFilter(screenTexel, prevCoord, viewPos);
                }

                indirectCurrent.a = maxEps(indirectCurrent.a * SSPT_VARIANCE_SCALE);
            }
        } else {
            currentCoord -= vec2(1.0, 0.0);
            float depth = sampleDepthMin4x4(currentCoord);

            if (depth < 1.0) {
                // depth += 0.38 * step(depth, 0.56);

                ivec2 currentTexel = screenTexel * 2 - ivec2(viewWidth, 0);
                vec3 worldNormal = FetchWorldNormal(sampleGbufferData0(currentTexel));
                float viewDistance = length(ScreenToViewSpace(vec3(currentCoord, depth)));

                indirectHistory = vec4(worldNormal, viewDistance);
            }
        }
    }
}