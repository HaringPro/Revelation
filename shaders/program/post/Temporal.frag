/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Temporal Anti-Aliasing

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 1,4 */
layout (location = 0) out vec4 temporalOut;
layout (location = 1) out vec3 clearOut;

#ifdef MOTION_BLUR
/* RENDERTARGETS: 1,4,3 */
layout (location = 2) out vec2 motionVectorOut;
#endif

//======// Input //===============================================================================//

// flat in float exposure;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Offset.glsl"

vec3 GetClosestFragment(in ivec2 texel, in float depth) {
    vec3 closestFragment = vec3(texel, depth);

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = offset3x3N[i] + texel;
        float sampleDepth = loadDepth0(sampleTexel);
        closestFragment = sampleDepth < closestFragment.z ? vec3(sampleTexel, sampleDepth) : closestFragment;
    }

    closestFragment.xy *= viewPixelSize;
    return closestFragment;
}

vec3 clipAABB(in vec3 boxMin, in vec3 boxMax, in vec3 prevSample) {
    vec3 p_clip = 0.5 * (boxMax + boxMin);
    vec3 e_clip = 0.5 * (boxMax - boxMin);

    vec3 v_clip = prevSample - p_clip;
    vec3 v_unit = v_clip / e_clip;
    vec3 a_unit = abs(v_unit);
    float ma_unit = maxOf(a_unit);

    if (ma_unit > 1.0) {
        return v_clip / ma_unit + p_clip;
    } else {
        return prevSample;
    }
}

// Approximation from SMAA presentation from siggraph 2016
vec4 textureCatmullRomFast(in sampler2D tex, in vec2 coord, in const float sharpness) {
    //vec2 viewSize = textureSize(sampler, 0);
    //vec2 pixelSize = 1.0 / viewSize;

    vec2 position = viewSize * coord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    vec2 w0 = -sharpness        * f3 + 2.0 * sharpness         * f2 - sharpness * f;
    vec2 w1 = (2.0 - sharpness) * f3 - (3.0 - sharpness)       * f2 + 1.0;
    vec2 w2 = (sharpness - 2.0) * f3 + (3.0 - 2.0 * sharpness) * f2 + sharpness * f;
    vec2 w3 = sharpness         * f3 - sharpness               * f2;

    vec2 w12 = w1 + w2;

    vec2 tc0 = viewPixelSize * (centerPosition - 1.0);
    vec2 tc3 = viewPixelSize * (centerPosition + 2.0);
    vec2 tc12 = viewPixelSize * (centerPosition + w2 / w12);

    float l0 = w12.x * w0.y;
    float l1 = w0.x  * w12.y;
    float l2 = w12.x * w12.y;
    float l3 = w3.x  * w12.y;
    float l4 = w12.x * w3.y;

    vec4 color =  texture(tex, vec2(tc12.x, tc0.y )) * l0
                + texture(tex, vec2(tc0.x,  tc12.y)) * l1
                + texture(tex, vec2(tc12.x, tc12.y)) * l2
                + texture(tex, vec2(tc3.x,  tc12.y)) * l3
                + texture(tex, vec2(tc12.x, tc3.y )) * l4;

    return color / (l0 + l1 + l2 + l3 + l4);
}

#define currentLoad(offset) sRGBToYCoCg(texelFetchOffset(colortex0, texel, 0, offset).rgb)

#define minOf(a, b, c, d, e, f, g, h, i) min(min(min(a, b), min(c, d)), min(min(e, f), min(min(g, h), i)))
#define maxOf(a, b, c, d, e, f, g, h, i) max(max(max(a, b), max(c, d)), max(max(e, f), max(max(g, h), i)))

#define mean(a, b, c, d, e, f, g, h, i) (a + b + c + d + e + f + g + h + i) * rcp(9.0)
#define sqrMean(a, b, c, d, e, f, g, h, i) (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h + i * i) * rcp(9.0)

vec4 CalculateTAA(in vec2 screenCoord, in vec2 motionVector) {
    ivec2 texel = uvToTexel(screenCoord + taaOffset * 0.5);

    vec3 currentSample = loadSceneColor(texel);
    vec2 prevCoord = screenCoord - motionVector;

    if (saturate(prevCoord) != prevCoord) return vec4(currentSample, 1.0);

    vec3 sample0 = sRGBToYCoCg(currentSample);
    vec3 sample1 = currentLoad(ivec2(-1,  1));
    vec3 sample2 = currentLoad(ivec2( 0,  1));
    vec3 sample3 = currentLoad(ivec2( 1,  1));
    vec3 sample4 = currentLoad(ivec2(-1,  0));
    vec3 sample5 = currentLoad(ivec2( 1,  0));
    vec3 sample6 = currentLoad(ivec2(-1, -1));
    vec3 sample7 = currentLoad(ivec2( 0, -1));
    vec3 sample8 = currentLoad(ivec2( 1, -1));

    vec3 clipMin = minOf(sample0, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);
    vec3 clipMax = maxOf(sample0, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);

    #ifdef TAA_VARIANCE_CLIPPING
        // Variance clip
        vec3 clipAvg = mean(sample0, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);
        vec3 clipAvg2 = sqrMean(sample0, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);

        vec3 variance = sqrt(abs(clipAvg2 - clipAvg * clipAvg)) * TAA_AGGRESSION;
        clipMin = min(clipAvg - variance, clipMin);
        clipMax = max(clipAvg + variance, clipMax);
    #endif

    #ifdef TAA_SHARPEN
        vec3 prevSample = textureCatmullRomFast(colortex1, prevCoord, TAA_SHARPNESS).rgb;
    #else
        vec3 prevSample = texture(colortex1, prevCoord).rgb;
    #endif

    prevSample = sRGBToYCoCg(prevSample);
    prevSample = clipAABB(clipMin, clipMax, prevSample);
    prevSample = YCoCgToSRGB(prevSample);

    float frameIndex = texture(colortex1, prevCoord).a;

    float blendWeight = clamp(++frameIndex, 1.0, TAA_MAX_ACCUM_FRAMES);
    blendWeight /= blendWeight + 1.0;

    vec2 pixelCenterDist = 1.0 - abs(fract(prevCoord * viewSize) * 2.0 - 1.0);
    float offcenterWeight = sqrt(pixelCenterDist.x * pixelCenterDist.y) * 0.25 + 0.75;
    blendWeight *= offcenterWeight;

    currentSample = mix(reinhard(currentSample), reinhard(prevSample), blendWeight);
    return vec4(invReinhard(currentSample), frameIndex);
}

//======// Main //================================================================================//
void main() {
    clearOut = vec3(0.0); // Clear the output buffer for bloom tiles

	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    float depth = loadDepth0(screenTexel);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    #ifdef TAA_CLOSEST_FRAGMENT
        vec3 closestFragment = GetClosestFragment(screenTexel, depth);
        vec2 motionVector = closestFragment.xy - Reproject(closestFragment).xy;
    #else
        vec2 motionVector = screenCoord - Reproject(vec3(screenCoord, depth)).xy;
    #endif

    #ifdef MOTION_BLUR
        motionVectorOut = depth < 0.56 ? motionVector * 0.2 : motionVector;
    #endif

    #ifdef TAA_ENABLED
        temporalOut = CalculateTAA(screenCoord, motionVector);
    #else
        temporalOut = vec4(loadSceneColor(screenTexel), 1.0/*  + texture(colortex1, screenCoord - motionVector).a */);
    #endif
}