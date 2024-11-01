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

#define RSM_SAMPLER colortex3
#define RSM_MAX_BLENDED_FRAMES 32.0 // [20.0 24.0 28.0 32.0 36.0 40.0 48.0 56.0 64.0 72.0 80.0 96.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 448.0 512.0 640.0 768.0 896.0 1024.0]

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 13 */
out vec4 indirectHistory;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

uniform sampler2D colortex13; // Previous indirect light

uniform float cameraVelocity;
uniform vec2 prevTaaOffset;

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"
#include "/lib/universal/Offset.glsl"

void TemporalFilter(in ivec2 screenTexel, in vec2 prevCoord, in vec3 viewPos) {
    vec4 prevLight = vec4(0.0);
    float sumWeight = 0.0;

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

    ivec2 shiftX = ivec2(int(viewWidth) >> 1, 0);
    ivec2 halfResBorder = (ivec2(viewSize) >> 1) - 1;

    for (uint i = 0u; i < 4u; ++i) {
        ivec2 sampleTexel = floorTexel + offset2x2[i];
        if (clamp(sampleTexel, ivec2(0), halfResBorder) == sampleTexel) {
            vec4 prevData = texelFetch(colortex13, sampleTexel + shiftX, 0);

            if ((abs(currViewDistance - prevData.w) - cameraVelocity) < 0.1 * currViewDistance) {
                float weight = weight[i];

                prevLight += texelFetch(colortex13, sampleTexel, 0) * weight;
                sumWeight += weight;
            }
        }
    }
    if (sumWeight > 1e-5) {
        prevLight /= sumWeight;

        indirectHistory.a = min(prevLight.a, RSM_MAX_BLENDED_FRAMES);

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
    float depth = readDepth0(texel);

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = (offset3x3N[i] << 1) + texel;
        float sampleDepth = readDepth0(sampleTexel);
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
            float depth = sampleDepthMin4x4(currentCoord);

            if (depth < 1.0) {
                ivec2 currentTexel = screenTexel << 1;
                // currentTexel = ivec2(closestFragment.xy * viewSize);
                vec3 worldNormal = FetchWorldNormal(readGbufferData0(currentTexel));

                vec3 screenPos = vec3(currentCoord, depth);
                vec3 viewPos = ScreenToViewSpace(screenPos);

                indirectHistory.rgb = texelFetch(RSM_SAMPLER, screenTexel, 0).rgb;
                indirectHistory.rgb = clamp16f(indirectHistory.rgb);

                vec2 prevCoord = Reproject(screenPos).xy;
		        if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
                    prevCoord *= 0.5;
                    TemporalFilter(screenTexel, prevCoord, viewPos);
                }
            }
        } else {
            currentCoord -= vec2(1.0, 0.0);
            float depth = sampleDepthMin4x4(currentCoord);

            if (depth < 1.0) {
                ivec2 currentTexel = (screenTexel << 1) - ivec2(int(viewWidth), 0);
                vec3 worldNormal = FetchWorldNormal(readGbufferData0(currentTexel));
                float viewDistance = length(ScreenToViewSpace(vec3(currentCoord, depth)));

                indirectHistory = vec4(worldNormal, viewDistance);
            }
        }
    }
}