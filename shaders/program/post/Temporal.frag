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
/* RENDERTARGETS: 1,4,2 */
layout (location = 2) out vec2 velocityOut;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D colortex0; // Scene data
uniform sampler2D colortex1; // Scene history

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform float near;
uniform float far;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec2 viewSize;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Offset.glsl"

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

#define currentLoad(offset) RGBtoYCoCgR(sampleSceneColor(texel + offset));

#define maxOf(a, b, c, d, e, f, g, h, i) max(a, max(b, max(c, max(d, max(e, max(f, max(g, max(h, i))))))))
#define minOf(a, b, c, d, e, f, g, h, i) min(a, min(b, min(c, min(d, min(e, min(f, min(g, min(h, i))))))))

vec4 CalculateTAA(in vec2 screenCoord, in vec2 velocity) {
    ivec2 texel = rawCoord(screenCoord + taaOffset * 0.5);

    vec3 currentSample = sampleSceneColor(texel);
    vec2 prevCoord = screenCoord - velocity;

    if (saturate(prevCoord) != prevCoord) return vec4(currentSample, 0.0);

    vec3 sample0 = RGBtoYCoCgR(currentSample);

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
        vec3 clipAvg = (sample0 + sample1 + sample2 + sample3 + sample4 + sample5 + sample6 + sample7 + sample8) * rcp(9.0);
        vec3 clipAvg2 = (sample0 * sample0 + sample1 * sample1 + sample2 * sample2 + sample3 * sample3 + sample4 * sample4 + sample5 * sample5 + sample6 * sample6 + sample7 * sample7 + sample8 * sample8) * rcp(9.0);

        vec3 variance = sqrt(abs(clipAvg2 - clipAvg * clipAvg)) * TAA_AGGRESSION;
        clipMin = min(clipAvg - variance, clipMin);
        clipMax = max(clipAvg + variance, clipMax);
    #endif

    #ifdef TAA_SHARPEN
        vec3 prevSample = textureCatmullRomFast(colortex1, prevCoord, TAA_SHARPNESS).rgb;
    #else
        vec3 prevSample = texture(colortex1, prevCoord).rgb;
    #endif

    prevSample = RGBtoYCoCgR(prevSample);
    prevSample = clipAABB(clipMin, clipMax, prevSample);

    prevSample = YCoCgRtoRGB(prevSample);

    float frameIndex = texelFetch(colortex1, rawCoord(prevCoord), 0).a;

    float blendWeight = clamp(++frameIndex, 1.0, TAA_MAX_BLENDED_FRAMES);
    blendWeight /= blendWeight + 1.0;

    vec2 distanceToPixelCenter = 1.0 - abs(fract(prevCoord * viewSize) * 2.0 - 1.0);
    float offcenterWeight = sqrt(distanceToPixelCenter.x * distanceToPixelCenter.y) * 0.25 + 0.75;
    blendWeight *= offcenterWeight;

    currentSample = mix(reinhard(currentSample), reinhard(prevSample), blendWeight);
    return vec4(invReinhard(currentSample), frameIndex * offcenterWeight);
}

//======// Main //================================================================================//
void main() {
    clearOut = vec3(0.0); // Clear the output buffer for bloom tiles

	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    float depth = sampleDepth(screenTexel);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    #ifdef TAA_CLOSEST_FRAGMNET
        vec3 closestFragment = GetClosestFragment(screenTexel, depth);
        vec2 velocity = closestFragment.xy - Reproject(closestFragment).xy;
    #else
        vec2 velocity = screenCoord - Reproject(vec3(screenCoord, depth)).xy;
    #endif

    #ifdef MOTION_BLUR
        velocityOut = velocity;
    #endif

    temporalOut = clamp16f(CalculateTAA(screenCoord, velocity));
}