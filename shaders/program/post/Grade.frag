/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Post-processing compositing

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define TONE_MAPPER 1 // [0 1 2 3 16 17 32 33 48]
#define HDR_TONE_MAPPER 33 // [0 3 16 17 32 33]

// 0: disables gamut compression, 1: Rec.2020, 2: P3-D65
#define ACES_HDR_TARGET_GAMUT 1 // [0 1 2]

#define GAMMA_CORRECTION 2.2 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0]

#define BLOOM_BLENDING_MODE 1 // [0 1 2]
#define BLOOM_INTENSITY 1.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]
#define BLOOMY_FOG_INTENSITY 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

#define PURKINJE_SHIFT
// #define PURKINJE_SHIFT_NOISE
#define PURKINJE_SHIFT_STRENGTH 0.2 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define PURKINJE_SHIFT_R 0.56 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
#define PURKINJE_SHIFT_G 0.78 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
#define PURKINJE_SHIFT_B 1.0  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

//======// Output //==============================================================================//

#if SR_ENABLE
// When super resolution is enabled, this pass will be running at the original resolution
/* RENDERTARGETS: 5 */
#else
/* RENDERTARGETS: 0 */
#endif
out vec3 color; // Tonemapped output

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

void CombineBloomAndFog(inout vec3 scene, ivec2 texel, float exposure) {
    #if SR_DISABLE
        vec2 screenCoord = texelToUvScaled(texel);
    #else
        vec2 screenCoord = texelToUv(texel);
    #endif

	vec3 bloomData = texture(colortex4, screenCoord * 0.5).rgb;

	float bloomIntensity = BLOOM_INTENSITY * 0.1;

	#ifdef BLOOMY_FOG
		float fogMask = texture(colortex0, screenCoord + taaJitter * 0.5).w;
		bloomIntensity = max(bloomIntensity, fogMask * BLOOMY_FOG_INTENSITY);
	#endif

	// Exposure adaptation
	bloomIntensity /= max(exposure, 1.0) + 1.0;

	#if BLOOM_BLENDING_MODE == 0
		scene += bloomData * bloomIntensity;
	#elif BLOOM_BLENDING_MODE == 1
		scene = mix(scene, bloomData, bloomIntensity);
	#else
		scene = (scene + bloomData * bloomIntensity) / (1.0 + bloomIntensity * 0.5);
	#endif

	if (rainStrength > 1e-2) {
		float rainAlpha = texture(colortex6, screenCoord).a;
		rainAlpha = oms(rainAlpha) * RAIN_VISIBILITY;
		scene = scene * oms(rainAlpha) + bloomData * rainAlpha * 1.25;
	}
}

// See section 3.4 of http://www.diva-portal.org/smash/get/diva2:24136/FULLTEXT01.pdf
vec3 ScotopicVision(vec3 color, float exposure) {
	const vec3 rodResponse = vec3(0.05, 0.55, 0.60);
	const vec3 tint = vec3(PURKINJE_SHIFT_R, PURKINJE_SHIFT_G, PURKINJE_SHIFT_B);

	vec3 xyz = color * sRGB_2_XYZ;
	vec3 scotopic = xyz * max0(1.33 * (1.0 + (xyz.y + xyz.z) / xyz.x) - 1.68);

	float rodLuminance = dot(scotopic * XYZ_2_sRGB, rodResponse);
	float mesopicFactor = saturate(log2(1.0 + exposure) / (2.0 + 4.0 * rodLuminance));

	#ifdef PURKINJE_SHIFT_NOISE
		rodLuminance *= 0.5 + SampleStbnVec1(ivec2(gl_GlobalInvocationID.xy), frameCounter);
	#endif

	return mix(color, rodLuminance * tint, PURKINJE_SHIFT_STRENGTH * mesopicFactor);
}

vec3 None(vec3 x) {
	return x;
}

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
// https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 Lottes(vec3 x) {
	x *= 2.0;

	const vec3 a      = vec3(1.35);
	const vec3 d      = vec3(0.92);
	const vec3 hdrMax = vec3(8.0);
	const vec3 midIn  = vec3(0.2);
	const vec3 midOut = vec3(0.3);

	const vec3 ad = a * d;
	const vec3 curvedMidIn = pow(midIn, a);
	const vec3 curvedHdrMax = pow(hdrMax, a);
	const vec3 b = -curvedMidIn + curvedHdrMax * midOut;
	const vec3 c = pow(hdrMax, ad) * curvedMidIn - curvedHdrMax * pow(midIn, ad) * midOut;

	return sRGBToLinear(pow(x, a) * (pow(hdrMax, ad) - pow(midIn, ad)) * midOut / (pow(x, ad) * b + c));
}

#include "/lib/post/ACES.glsl"
#include "/lib/post/AgX.glsl"
#include "/lib/post/GT.glsl"

#ifdef HDR_ENABLED
	#define TONE_MAPPER_ HDR_TONE_MAPPER
#else
	#define TONE_MAPPER_ TONE_MAPPER
#endif

#if TONE_MAPPER_ == TONEMAPPER_AgX_Minimal
	#define TONEMAPPING_FN AgX_Minimal
#elif TONE_MAPPER_ == TONEMAPPER_AgX_Full
	#define TONEMAPPING_FN AgX_Full
#elif TONE_MAPPER_ == TONEMAPPER_ACES_Fit
	#define TONEMAPPING_FN AcademyFit
#elif TONE_MAPPER_ == TONEMAPPER_ACES_2
	#define TONEMAPPING_FN ACES2
#elif TONE_MAPPER_ == TONEMAPPER_GT
	#define TONEMAPPING_FN GT
#elif TONE_MAPPER_ == TONEMAPPER_GT7
	#define TONEMAPPING_FN GT7
#elif TONE_MAPPER_ == TONEMAPPER_Lottes
	#define TONEMAPPING_FN Lottes
#else
	#define TONEMAPPING_FN None
#endif

//======// Main //================================================================================//
void main() {
    // When super resolution is enabled, texelPos will be at the original resolution
	ivec2 texelPos = ivec2(gl_FragCoord.xy);

	#if EXPOSURE_MODE == MANUAL
		float exposure = exp2(-MANUAL_EV);
	#else
		float exposure = exposure.value;
	#endif
    #if SR_DISABLE
	    #ifdef MOTION_BLUR
	    	color = texelFetch(colortex0, texelPos, 0).rgb;
	    #else
	    	color = texelFetch(colortex1, texelPos, 0).rgb;
	    #endif
    #else
        color = texelFetch(colortex5, texelPos, 0).rgb;
    #endif

	// Bloom and fog
	#ifdef BLOOM
        // When super resolution is enabled, bloom will be upscaled to the original resolution
		CombineBloomAndFog(color, texelPos, exposure);
	#endif

	// Debug sky environment map
	#ifdef DEBUG_SKY_MAP
		if (all(lessThan(texelPos, textureSize(skyEnvMapTex, 0)))) {
			color = texelFetch(skyEnvMapTex, texelPos, 0).rgb;
		}
	#endif

	#ifdef DEBUG_ATMOSPHERE_LUTS
		ivec2 tempTexel = texelPos;
		if (all(lessThan(tempTexel, textureSize(skyViewTex, 0)))) {
			color = DecodeRGBE8(texelFetch(skyViewTex, tempTexel, 0));
		}
		tempTexel.x -= textureSize(skyViewTex, 0).x;
		if (clamp(tempTexel, ivec2(0), textureSize(tLutTex, 0) - 1) == tempTexel) {
			color = texelFetch(tLutTex, tempTexel, 0).rgb * 64.0;
		}
		tempTexel.x -= textureSize(tLutTex, 0).x;
		if (clamp(tempTexel, ivec2(0), textureSize(msLutTex, 0) - 1) == tempTexel) {
			color = texelFetch(msLutTex, tempTexel, 0).rgb * 512.0;
		}
	#endif

	// Apply exposure
	color *= exposure;

	// Purkinje shift
	#ifdef PURKINJE_SHIFT
		color = ScotopicVision(color, exposure);
	#endif

	// Vignetting
	#ifdef VIGNETTE_ENABLED
        #if SR_DISABLE
		    vec2 ndcCoord = texelToUvScaled(texelPos) * 2.0 - 1.0;
        #else
            vec2 ndcCoord = texelToUv(texelPos) * 2.0 - 1.0;
        #endif
		ndcCoord.x *= mix(1.0, aspectRatio, VIGNETTE_ROUNDNESS);
		color *= exp2(-0.5 * VIGNETTE_STRENGTH * sdot(ndcCoord));
	#endif

	// Apply DRT
	{
		// Tone mapping
		color = TONEMAPPING_FN(color);
		#ifndef HDR_ENABLED
			// Working to display space
			color *= Rec2020_2_sRGB;
			color = saturate(pow(color, vec3(1.0 / GAMMA_CORRECTION)));
		#else
			// Limited in Rec2020 non negative linear value range for CAS
			color = max0(color);
		#endif
	}

	// Debug tone mapping plot
	#ifdef DEBUG_TONE_MAPPING_PLOT
		const float scale = 1.5;

        #if SR_DISABLE
        vec2 uv = texelToUvScaled(texelPos) * vec2(aspectRatio, 1.0) * scale;
        #else
        vec2 uv = texelToUv(texelPos) * vec2(aspectRatio, 1.0) * scale;
        #endif
        float plot = smoothstep(0.0, scale * scaledPixelSize.y, abs(uv.y - TONEMAPPING_FN(vec3(uv.x)).x));

		// Show LDR range
		color = vec3(0.25) * step(uv.x, 1.0);
		color = mix(vec3(1.0), color, plot);
	#endif
}
