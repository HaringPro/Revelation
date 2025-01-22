/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: RSM accumulation
	Reference:  https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf
                https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 13 */
out vec4 indirectHistory;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"
#include "/lib/universal/Offset.glsl"

void TemporalFilter(in ivec2 screenTexel, in vec2 prevCoord, in vec3 viewPos, in vec3 worldNormal) {
    vec4 prevLight = vec4(0.0);
    float sumWeight = 0.0;

    float currViewDistance = length(viewPos);

    prevCoord += (prevTaaOffset - taaOffset) * 0.125;

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
                sumWeight += weight;
            }
        }
    }
    if (sumWeight > 1e-5) {
        prevLight *= 1.0 / sumWeight;

        indirectHistory.a = min(prevLight.a, RSM_MAX_ACCUM_FRAMES);

        float alpha = rcp(++indirectHistory.a);
        indirectHistory.rgb = mix(prevLight.rgb, indirectHistory.rgb, alpha);
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

vec3 SpatialCurrent(in ivec2 texel, in vec3 worldNormal) {
    const float kernel[2][2] = {{0.25, 0.125}, {0.125, 0.0625}};

	ivec2 offsetToBR = ivec2(halfViewSize.x, 0);
    ivec2 texelEnd = ivec2(halfViewEnd);

    float sumWeight = kernel[0][0];
    vec3 indirectData = texelFetch(colortex3, texel, 0).rgb * sumWeight;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sampleTexel = clamp(texel + ivec2(x, y), ivec2(0), texelEnd);
            vec3 sampleColor = texelFetch(colortex3, sampleTexel, 0).rgb;
            vec3 sampleNormal = FetchWorldNormal(loadGbufferData0(sampleTexel << 1));

            float weight = kernel[abs(x)][abs(y)];
            weight *= pow16(max0(dot(sampleNormal, worldNormal)));

            indirectData += sampleColor * weight;
            sumWeight += weight;
        }
    }

    return indirectData * rcp(sumWeight);
}

//======// Main //================================================================================//
void main() {
    vec2 currentCoord = gl_FragCoord.xy * viewPixelSize * 2.0;

    if (currentCoord.y < 1.0) {
        ivec2 screenTexel = ivec2(gl_FragCoord.xy);

        if (currentCoord.x < 1.0) {
            ivec2 currentTexel = screenTexel << 1;
            // vec3 closestFragment = GetClosestFragment(currentTexel, depth);
            float depth = loadDepth0(currentTexel);

            if (depth < 1.0) {
                // currentTexel = ivec2(closestFragment.xy * viewSize);

                vec3 screenPos = vec3(currentCoord, depth);

                vec3 worldNormal = FetchWorldNormal(loadGbufferData0(currentTexel));
                indirectHistory.rgb = SpatialCurrent(screenTexel, worldNormal);

                vec2 prevCoord = Reproject(screenPos).xy;
		        if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
                    vec3 viewPos = ScreenToViewSpace(screenPos);
                    TemporalFilter(screenTexel, prevCoord, viewPos, worldNormal);
                }
            }
        } else {
            ivec2 currentTexel = (screenTexel << 1) - ivec2(int(viewWidth), 0);
            float depth = loadDepth0(currentTexel);

            if (depth < 1.0) {
                vec3 worldNormal = FetchWorldNormal(loadGbufferData0(currentTexel));
                float viewDistance = length(ScreenToViewSpace(vec3(currentCoord - vec2(1.0, 0.0), depth)));

                indirectHistory = vec4(worldNormal, viewDistance);
            }
        }
    }
}