/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Contrast adaptive sharpening and final output

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Config //==============================================================================//

#include "/config.glsl"

//======// Output //==============================================================================//

out vec3 finalOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

#define minOf(a, b, c, d, e, f, g, h, i) min(min(min(a, b), min(c, d)), min(min(e, f), min(min(g, h), i)))
#define maxOf(a, b, c, d, e, f, g, h, i) max(max(max(a, b), max(c, d)), max(max(e, f), max(max(g, h), i)))

#define casLoad(offset) texelFetchOffset(colortex0, texel, 0, offset).rgb

// Contrast Adaptive Sharpening (CAS)
// Reference: Lou Kramer, FidelityFX CAS, AMD Developer Day 2019,
// https://gpuopen.com/wp-content/uploads/2019/07/FidelityFX-CAS.pptx
vec3 FsrCasFilter(in ivec2 texel) {
	#ifndef CAS_ENABLED
		return casLoad(ivec2(0, 0));
	#endif

	vec3 a = casLoad(ivec2(-1, -1));
	vec3 b = casLoad(ivec2( 0, -1));
	vec3 c = casLoad(ivec2( 1, -1));
	vec3 d = casLoad(ivec2(-1,  0));
	vec3 e = casLoad(ivec2( 0,  0));
	vec3 f = casLoad(ivec2( 1,  0));
	vec3 g = casLoad(ivec2(-1,  1));
	vec3 h = casLoad(ivec2( 0,  1));
	vec3 i = casLoad(ivec2( 1,  1));

	vec3 minColor = minOf(a, b, c, d, e, f, g, h, i);
	vec3 maxColor = maxOf(a, b, c, d, e, f, g, h, i);

    vec3 sharpeningAmount = sqrt(min(1.0 - maxColor, minColor) / maxColor);
    vec3 w = sharpeningAmount * -(0.125 + 0.075 * CAS_STRENGTH);

	return ((b + d + f + h) * w + e) / (4.0 * w + 1.0);
}

#ifdef FSR_ENABLED
	#include "/lib/post/FSR.glsl"
#endif

//================================================================================================//

// Approximation from SMAA presentation from siggraph 2016
vec3 textureCatmullRomFast(in sampler2D tex, in vec2 position, in const float sharpness) {
	//vec2 screenSize = textureSize(sampler, 0);
	//vec2 viewPixelSize = 1.0 / screenSize;

	//vec2 position = screenSize * coord;
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

	vec3 color =  texture(tex, vec2(tc12.x, tc0.y )).rgb * l0
				+ texture(tex, vec2(tc0.x,  tc12.y)).rgb * l1
				+ texture(tex, vec2(tc12.x, tc12.y)).rgb * l2
				+ texture(tex, vec2(tc3.x,  tc12.y)).rgb * l3
				+ texture(tex, vec2(tc12.x, tc3.y )).rgb * l4;

	return color / (l0 + l1 + l2 + l3 + l4);
}

#include "/lib/universal/TextRenderer.glsl"

void HistogramDisplay(inout vec3 color, in ivec2 texel) {
    const int binWidth = 2;

    if (all(lessThan(texel, ivec2(HISTOGRAM_BIN_COUNT * binWidth, 256)))) {
		int binIndex = texel.x / binWidth;
		uint binValue = global.exposure.histogram[binIndex];

		color = vec3(step(texel.y + 1, binValue));
	}
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	#ifdef DEBUG_BLOOM_TILES
		finalOut = texelFetch(colortex4, screenTexel, 0).rgb;
	#else
		if (abs(MC_RENDER_QUALITY - 1.0) < 1e-2) {
			finalOut = FsrCasFilter(screenTexel);
			#ifdef FSR_ENABLED
				} else if (MC_RENDER_QUALITY < 1.0) {
					finalOut = FsrRcasF(screenTexel);
			#endif
		} else {
			finalOut = textureCatmullRomFast(colortex0, gl_FragCoord.xy * MC_RENDER_QUALITY, 0.6);
		}
	#endif

	// Apply gamma correction
	finalOut = linearToSRGBApprox(finalOut);

	// Text display
	#if 0
		finalOut += renderText(ivec2(100), 3, vec3(0.5));
		finalOut = saturate(finalOut);
	#endif

	// Time display
	#if 0
		const ivec2 size = ivec2(30, 200);
		const int strokewidth = 3;
		const ivec2 start = ivec2(60, 200);
		const ivec2 end = start + size;
		const int center = (start.y + end.y) >> 1;

		if (clamp(screenTexel, start - strokewidth, end + strokewidth) == screenTexel) {
			finalOut = vec3(0.0);
			if (clamp(screenTexel, start, end) == screenTexel && clamp(screenTexel.y, center - 1, center + 1) != screenTexel.y) {
				float t = 1.0 - sunAngle * 2.0 + step(0.5, sunAngle);
				if (screenTexel.y > start.y + t * size.y) {
					finalOut = sunAngle < 0.5 ? vec3(0.2, 0.7, 1.0) : vec3(0.08, 0.24, 0.4);
				} else {
					finalOut = vec3(1.0);
				}
			}
		}
	#endif

	#ifdef DEBUG_CLOUD_SHADOWS
		if (all(lessThan(screenTexel, textureSize(cloudShadowTex, 0)))) {
			finalOut = vec3(texelFetch(cloudShadowTex, screenTexel, 0).x);
		}
	#endif

	#ifdef DEBUG_SKY_COLOR
		if (all(lessThan(gl_FragCoord.xy * viewPixelSize, vec2(0.4)))) finalOut = skyColor;
	#endif

	#if 0
		HistogramDisplay(finalOut, screenTexel);
	#endif

	// Apply bayer dithering to reduce banding artifacts
	finalOut += (bayer16(gl_FragCoord.xy) - 0.5) * r255;
}