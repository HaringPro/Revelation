/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"
#include "/lib/utility/Uniform.inc"

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Offset.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,7 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out vec3 temporalOut;

//======// Function //============================================================================//

vec3 GetClosestFragment(in ivec2 texel, in float depth) {
    vec3 closestFragment = vec3(texel, depth);

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = offset3x3N[i] + texel;
        float sampleDepth = texelFetch(depthtex0, sampleTexel, 0).x;
        closestFragment = sampleDepth < closestFragment.z ? vec3(sampleTexel, sampleDepth) : closestFragment;
    }

    closestFragment.xy *= viewPixelSize;
    return closestFragment;
}

vec3 reinhard(in vec3 color) {
    return color / (1.0 + GetLuminance(color));
}
vec3 invReinhard(in vec3 color) {
    return color / (1.0 - GetLuminance(color));
}

vec3 RGBtoYCoCgR(in vec3 rgbColor) {
    vec3 YCoCgRColor;

    YCoCgRColor.y = rgbColor.r - rgbColor.b;
    float temp = rgbColor.b + YCoCgRColor.y * 0.5;
    YCoCgRColor.z = rgbColor.g - temp;
    YCoCgRColor.x = temp + YCoCgRColor.z * 0.5;

    return YCoCgRColor;
}
vec3 YCoCgRtoRGB(in vec3 YCoCgRColor) {
    vec3 rgbColor;

    float temp = YCoCgRColor.x - YCoCgRColor.z * 0.5;
    rgbColor.g = YCoCgRColor.z + temp;
    rgbColor.b = temp - YCoCgRColor.y * 0.5;
    rgbColor.r = rgbColor.b + YCoCgRColor.y;

    return rgbColor;
}

vec3 clipAABB(in vec3 boxMin, in vec3 boxMax, in vec3 previousSample) {
    vec3 p_clip = 0.5 * (boxMax + boxMin);
    vec3 e_clip = 0.5 * (boxMax - boxMin);

    vec3 v_clip = previousSample - p_clip;
    vec3 v_unit = v_clip / e_clip;
    vec3 a_unit = abs(v_unit);
    float ma_unit = maxOf(a_unit);

    if (ma_unit > 1.0) {
        return v_clip / ma_unit + p_clip;
    }else{
        return previousSample;
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

#define sampleColor(offset) RGBtoYCoCgR(sampleSceneColor(texel + offset));

vec3 CalculateTAA(in vec2 screenCoord, in vec2 velocity) {
    ivec2 texel = ivec2((screenCoord + taaOffset * 0.5) * viewSize);

    vec3 currentSample = sampleSceneColor(texel);
    vec2 previousCoord = screenCoord - velocity;

    if (saturate(previousCoord) != previousCoord) return currentSample;

    vec3 col0 = RGBtoYCoCgR(currentSample);

    vec3 col1 = sampleColor(ivec2(-1,  1));
    vec3 col2 = sampleColor(ivec2( 0,  1));
    vec3 col3 = sampleColor(ivec2( 1,  1));
    vec3 col4 = sampleColor(ivec2(-1,  0));
    vec3 col5 = sampleColor(ivec2( 1,  0));
    vec3 col6 = sampleColor(ivec2(-1, -1));
    vec3 col7 = sampleColor(ivec2( 0, -1));
    vec3 col8 = sampleColor(ivec2( 1, -1));

    // Variance clip
    vec3 clipAvg = (col0 + col1 + col2 + col3 + col4 + col5 + col6 + col7 + col8) * rcp(9.0);
    vec3 sqrVar = (col0 * col0 + col1 * col1 + col2 * col2 + col3 * col3 + col4 * col4 + col5 * col5 + col6 * col6 + col7 * col7 + col8 * col8) * rcp(9.0);

    vec3 variance = sqrt(abs(sqrVar - clipAvg * clipAvg));
    vec3 clipMin = min(clipAvg - variance * 1.25, col0);
    vec3 clipMax = max(clipAvg + variance * 1.25, col0);

    #ifdef TAA_SHARPEN
        vec3 previousSample = textureCatmullRomFast(colortex7, previousCoord, TAA_SHARPNESS).rgb;
    #else
        vec3 previousSample = texture(colortex7, previousCoord).rgb;
    #endif

    previousSample = RGBtoYCoCgR(previousSample);
    previousSample = clipAABB(clipMin, clipMax, previousSample);

    previousSample = YCoCgRtoRGB(previousSample);

    float blendWeight = 0.97;
    vec2 pixelVelocity = 1.0 - abs(fract(previousCoord * viewSize) * 2.0 - 1.0);
    blendWeight *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75;

    return invReinhard(mix(reinhard(currentSample), reinhard(previousSample), blendWeight));
}

//======// Main //================================================================================//
void main() {
    sceneOut = vec3(0.0); // Clear colortex0 for bloom tile pass

	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    float depth = sampleDepth(screenTexel);

    vec3 closestFragment = GetClosestFragment(screenTexel, depth);
    vec2 velocity = closestFragment.xy - Reproject(closestFragment).xy;

	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
    temporalOut = clamp16f(CalculateTAA(screenCoord, velocity));
}