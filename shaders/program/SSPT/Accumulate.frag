/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Accumulation for SSPT and variance estimation
	Reference:  https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering://svgf_preprint.pdf
                https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 3,13,14 */
layout (location = 0) out vec4 indirectCurrent;
layout (location = 1) out vec4 indirectHistory;
layout (location = 2) out vec2 momentsHistory;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"
#include "/lib/universal/Offset.glsl"

float EstimateSpatialVariance(in ivec2 texel, in float luma) {
    const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};

    ivec2 texelEnd = ivec2(halfViewEnd);

    float sqLuma = luma * luma;
    luma *= kernel[0][0], sqLuma *= kernel[0][0];

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sampleTexel = clamp(texel + ivec2(x, y), ivec2(0), texelEnd);
            float weight = kernel[abs(x)][abs(y)];
            float sampleLuma = GetLuminance(texelFetch(colortex3, sampleTexel, 0).rgb);

            luma   += sampleLuma * weight;
            sqLuma += sampleLuma * sampleLuma * weight;
        }
    }
    return max0(sqLuma - luma * luma);
}

vec4 SpatialCurrent(in ivec2 texel) {
    // const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};
    const float h[24] = {1.0 / 256.0,   1.0 / 64.0,     3.0 / 128.0,    1.0 / 64.0, 1.0 / 256.0,
                         1.0 / 64.0,    1.0 / 16.0,     3.0 / 32.0,     1.0 / 16.0, 1.0 / 64.0,
                         3.0 / 128.0,   3.0 / 32.0,  /* 9.0 / 64.0 */   3.0 / 32.0, 3.0 / 128.0,
                         1.0 / 64.0,    1.0 / 16.0,     3.0 / 32.0,     1.0 / 16.0, 1.0 / 64.0,
                         1.0 / 256.0,   1.0 / 64.0,     3.0 / 128.0,    1.0 / 64.0, 1.0 / 256.0};

    ivec2 texelEnd = ivec2(halfViewEnd);

    vec3 filteredColor = texelFetch(colortex3, texel, 0).rgb;

    // float luma = GetLuminance(filteredColor), sqLuma = luma * luma, maxLuma = luma;
    float maxLuma = GetLuminance(filteredColor);
    filteredColor *= 9.0 / 64.0;

    for (uint i = 0u; i < 24u; ++i) {
        ivec2 sampleTexel = clamp(texel + offset5x5N[i], ivec2(0), texelEnd);
        vec3 currentColor = texelFetch(colortex3, sampleTexel, 0).rgb;

        float weight = h[i];
        float sampleLuma = GetLuminance(currentColor);
        maxLuma = max(maxLuma, sampleLuma);

        filteredColor += currentColor * weight;
        // luma   += sampleLuma;
        // sqLuma += sampleLuma * sampleLuma;
    }

    // momentsHistory = vec2(luma, sqLuma) * rcp(25.0);
    return vec4(filteredColor, maxLuma);
}

void TemporalFilter(in ivec2 screenTexel, in vec2 prevCoord, in vec3 viewPos, in vec3 worldNormal) {
    vec4 prevLight = vec4(0.0);
    vec2 prevMoments = vec2(0.0);
    float sumWeight = 0.0;

    float currViewDistance = length(viewPos);

    prevCoord += (prevTaaOffset - taaOffset) * 0.25;

    // Custom bilinear filter
    vec2 prevTexel = prevCoord * 0.5 * viewSize - vec2(0.5);
    ivec2 floorTexel = ivec2(floor(prevTexel));
    vec2 fractTexel = fract(prevTexel - floorTexel);

    float bilinearWeight[4] = {
        oneMinus(fractTexel.x) * oneMinus(fractTexel.y),
        fractTexel.x           * oneMinus(fractTexel.y),
        oneMinus(fractTexel.x) * fractTexel.y,
        fractTexel.x           * fractTexel.y
    };

    ivec2 offsetToBR = ivec2(halfViewSize.x, 0);
    ivec2 texelEnd = ivec2(halfViewEnd);

    for (uint i = 0u; i < 4u; ++i) {
        ivec2 sampleTexel = floorTexel + offset2x2[i];
        if (clamp(sampleTexel, ivec2(0), texelEnd) == sampleTexel) {
            vec4 prevData = texelFetch(colortex13, sampleTexel + offsetToBR, 0);

            float diffZ = abs((currViewDistance - prevData.w) - cameraVelocity) / abs(currViewDistance);
            float diffN = dot(prevData.xyz, worldNormal);
            if (diffZ < 0.1 && diffN > 0.5) {
                float weight = bilinearWeight[i];

                prevLight += texelFetch(colortex13, sampleTexel, 0) * weight;
                prevMoments += texelFetch(colortex14, sampleTexel, 0).xy * weight;
                sumWeight += weight;
            }
        }
    }

    if (sumWeight > 1e-5) {
        sumWeight = rcp(sumWeight);
        prevLight *= sumWeight;
        prevMoments *= sumWeight;

        // indirectCurrent.rgb = SpatialCurrent(screenTexel);
        indirectCurrent.rgb = texelFetch(colortex3, screenTexel, 0).rgb;
        // indirectCurrent.rgb = textureSmoothFilter(colortex3, vec2(screenTexel + offsetToBR) * viewPixelSize).rgb;

        indirectHistory.a = min(++prevLight.a, SSPT_MAX_ACCUM_FRAMES);
        float alpha = rcp(indirectHistory.a);

        indirectCurrent.rgb = indirectHistory.rgb = mix(prevLight.rgb, indirectCurrent.rgb, alpha);
        indirectHistory.rgb = satU16f(indirectHistory.rgb);

        float luminance = GetLuminance(indirectCurrent.rgb);

        vec2 currMoments = vec2(luminance, luminance * luminance);
        momentsHistory = mix(prevMoments, currMoments, max(0.05, alpha));

        // See section 4.2 of the paper
        if (indirectHistory.a > 4.5) {
            indirectCurrent.a = max0(momentsHistory.y - momentsHistory.x * momentsHistory.x);
        } else {
            indirectCurrent.a = EstimateSpatialVariance(screenTexel, luminance);
        }
    } else {
        indirectCurrent = SpatialCurrent(screenTexel);
        indirectHistory = vec4(indirectCurrent.rgb, 1.0);
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
    float depth = loadDepth0(texel);

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = (offset3x3N[i] << 1) + texel;
        float sampleDepth = loadDepth0(sampleTexel);
        depth = min(depth, sampleDepth);
    }

    return depth;
}

//======// Main //================================================================================//
void main() {
    vec2 currentCoord = gl_FragCoord.xy * viewPixelSize * 2.0;

    if (currentCoord.y < 1.0) {
        ivec2 screenTexel = ivec2(gl_FragCoord.xy);

        if (currentCoord.x < 1.0) {
            // vec3 closestFragment = GetClosestFragment(currentTexel, depth);
            // float depth = sampleDepthMin4x4(currentCoord);
            ivec2 currentTexel = screenTexel << 1;
            float depth = loadDepth0(currentTexel);
            #if defined DISTANT_HORIZONS
                bool dhTerrainMask = depth > 0.999999;
                if (dhTerrainMask) depth = loadDepth0DH(currentTexel);
            #endif

            indirectCurrent = indirectHistory = vec4(vec3(0.0), 1.0);

            momentsHistory = vec2(0.0);

            if (depth < 1.0) {
                // currentTexel = ivec2(closestFragment.xy * viewSize);

                vec3 screenPos = vec3(currentCoord, depth);

                vec2 prevCoord = Reproject(screenPos).xy;
                #if defined DISTANT_HORIZONS
                    if (dhTerrainMask) prevCoord = ReprojectDH(screenPos).xy;
                #endif
                if (saturate(prevCoord) != prevCoord || worldTimeChanged) {
                    indirectCurrent = SpatialCurrent(screenTexel);
                    indirectHistory = vec4(indirectCurrent.rgb, 1.0);
                } else {
                    vec3 viewPos = ScreenToViewSpace(screenPos);
                    #if defined DISTANT_HORIZONS
                        if (dhTerrainMask) viewPos = ScreenToViewSpaceDH(screenPos);
                    #endif
                    vec3 worldNormal = FetchWorldNormal(loadGbufferData0(currentTexel));
                    TemporalFilter(screenTexel, prevCoord, viewPos, worldNormal);
                }
            }
        } else {
            ivec2 currentTexel = (screenTexel << 1) - ivec2(viewWidth, 0);
            float depth = loadDepth0(currentTexel);
            #if defined DISTANT_HORIZONS
                bool dhTerrainMask = depth > 0.999999;
                if (dhTerrainMask) depth = loadDepth0DH(currentTexel);
            #endif

            if (depth < 1.0) {
                vec3 worldNormal = FetchWorldNormal(loadGbufferData0(currentTexel));
                vec3 screenPos = vec3(currentCoord - vec2(1.0, 0.0), depth);
                vec3 viewPos = ScreenToViewSpace(screenPos);
                #if defined DISTANT_HORIZONS
                    if (dhTerrainMask) viewPos = ScreenToViewSpaceDH(screenPos);
                #endif
                float viewDistance = length(viewPos);

                indirectHistory = vec4(worldNormal, viewDistance);
            }
        }
    }
}