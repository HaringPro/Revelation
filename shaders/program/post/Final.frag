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

// Contrast Adaptive Sharpening (CAS)
// Reference: Lou Kramer, FidelityFX CAS, AMD Developer Day 2019,
// https://gpuopen.com/wp-content/uploads/2019/07/FidelityFX-CAS.pptx
// https://github.com/GPUOpen-Effects/FidelityFX-CAS
vec3 FFXCasFilter(in ivec2 texel, in float sharpness) {
	#define CasLoad(offset) texelFetchOffset(colortex8, texel, 0, offset).rgb

	#ifndef CAS_ENABLED
		return CasLoad(ivec2(0, 0));
	#endif

	// a b c
	// d e f
	// g h i
	vec3 a = CasLoad(ivec2(-1, -1));
	vec3 b = CasLoad(ivec2( 0, -1));
	vec3 c = CasLoad(ivec2( 1, -1));
	vec3 d = CasLoad(ivec2(-1,  0));
	vec3 e = CasLoad(ivec2( 0,  0));
	vec3 f = CasLoad(ivec2( 1,  0));
	vec3 g = CasLoad(ivec2(-1,  1));
	vec3 h = CasLoad(ivec2( 0,  1));
	vec3 i = CasLoad(ivec2( 1,  1));

	// Soft min and max.
	//  a b c             b
	//  d e f * 0.5  +  d e f * 0.5
	//  g h i             h
	// These are 2.0x bigger (factored out the extra multiply).
	vec3 minCol = min(min(min(d, e), min(f, b)), h);
		minCol += min(min(min(a, c), min(g, i)), minCol);
	vec3 maxCol = max(max(max(d, e), max(f, b)), h);
		maxCol += max(max(max(a, c), max(g, i)), maxCol);

    vec3 amp = approxSqrt(saturate(min(minCol, 2.0 - maxCol) / maxCol));

	// Filter shape.
	//  0 w 0
	//  w 1 w
	//  0 w 0
    vec3 w = amp * -rcp(mix(8.0, 5.0, sharpness));
	return saturate(((b + d + f + h) * w + e) / (1.0 + 4.0 * w));
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
    ivec2 texelPos = ivec2(gl_FragCoord.xy);

	// Update SSBO
	global.prevWorldTime = worldTime;

	#ifdef DEBUG_BLOOM_TILES
		finalOut = texelFetch(colortex4, texelPos, 0).rgb;
	#else
		finalOut = FFXCasFilter(texelPos, CAS_STRENGTH);
	#endif

	// Text display
	#if 0
		finalOut += renderText(ivec2(100), 3, vec3(0.5));
		finalOut = saturate(finalOut);
	#endif

	#ifdef DEBUG_CLOUD_SHADOWS
		if (all(lessThan(texelPos, textureSize(cloudShadowTex, 0)))) {
			finalOut = vec3(texelFetch(cloudShadowTex, texelPos, 0).x);
		}
	#endif

	#ifdef DEBUG_CLOUD_MAP
		ivec2 tempTexel = texelPos;
		if (all(lessThan(tempTexel, textureSize(cloudMapTex, 0)))) {
			finalOut = vec3(texelFetch(cloudMapTex, tempTexel, 0).x);
		}
		tempTexel -= ivec2(textureSize(cloudMapTex, 0).x, 0);
		if (all(greaterThanEqual(tempTexel, ivec2(0)) && lessThan(tempTexel, textureSize(cloudMapTex, 0)))) {
			finalOut = vec3(texelFetch(cloudMapTex, tempTexel, 0).y);
		}
	#endif

	#ifdef DEBUG_CLOUD_NOISE
		if (all(lessThan(texelPos, textureSize(baseNoiseTex, 0).xy))) {
			finalOut = vec3(texelFetch(baseNoiseTex, ivec3(texelPos, 0), 0).x);
		}
	#endif

	#ifdef DEBUG_SKY_COLOR
		if (all(lessThan(gl_FragCoord.xy * viewPixelSize, vec2(0.25)))) finalOut = skyColor;
	#endif

	#if 0
		HistogramDisplay(finalOut, texelPos);
	#endif

	// Apply bayer dithering to reduce banding artifacts
	finalOut += (bayer16(gl_FragCoord.xy) - 0.5) * r255;
}