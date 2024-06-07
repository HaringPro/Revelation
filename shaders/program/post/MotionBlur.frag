/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#ifdef MOTION_BLUR
#endif

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2 */
out vec3 blurColor;

//======// Uniform //=============================================================================//

uniform sampler2D colortex2;
uniform sampler2D colortex5;

uniform vec2 viewSize;
uniform vec2 viewPixelSize;

//======// Function //============================================================================//

float InterleavedGradientNoise(in vec2 coord) {
    return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y));
}

vec3 MotionBlur() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec2 velocity = texelFetch(colortex2, screenTexel, 0).xy;

	if (length(velocity) < 1e-7) return texelFetch(colortex5, screenTexel, 0).rgb;

    //velocity = clamp(velocity * 0.1, -0.28, 0.28);
	const float rSteps = rcp(float(MOTION_BLUR_SAMPLES));
	velocity *= MOTION_BLUR_STRENGTH * rSteps / (1.0 + length(velocity)) * viewSize;

	float dither = InterleavedGradientNoise(gl_FragCoord.xy);

    vec2 sampleCoord = screenCoord * viewSize + velocity * dither;
	sampleCoord -= velocity * MOTION_BLUR_SAMPLES * 0.5;

	vec3 blurColor = vec3(0.0);

	for (uint i = 0u; i < MOTION_BLUR_SAMPLES; ++i, sampleCoord += velocity) {
        blurColor += texelFetch(colortex5, ivec2(clamp(sampleCoord, vec2(2.0), viewSize - 2.0)), 0).rgb;
	}

	return clamp16f(blurColor * rSteps);
}

//======// Main //================================================================================//
void main() {
	blurColor = MotionBlur();
}
