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
#define PURKINJE_SHIFT_STRENGTH 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

#define COLOR_CONTRAST 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define COLOR_SATURATION 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 color; // Tonemapped output

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

void CombineBloomAndFog(inout vec3 scene, vec2 screenCoord, float exposure) {
	vec3 bloomData = texture(colortex4, screenCoord * 0.5).rgb;

	float bloomIntensity = BLOOM_INTENSITY * 0.1;

	#ifdef BLOOMY_FOG
		float fogMask = texture(colortex0, scaleScreenUv(screenCoord)).w;
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
		float rainAlpha = texture(colortex6, scaleScreenUv(screenCoord)).a;
		rainAlpha = oms(rainAlpha) * RAIN_VISIBILITY;
		scene = scene * oms(rainAlpha) + bloomData * rainAlpha * 1.25;
	}
}

float MesopicAdaptation(float exposure) {
	#if EXPOSURE_MODE == MANUAL
		float adaptedLogLuminance = log2(0.18 / exposure);
	#else
		float exposureEv = log2(maxEps(exposure) * rcp(0.18));
		float exposureCurve = mix(0.65, 1.0, nightVision);
		float adaptedLogLuminance = (AUTO_EV_BIAS - exposureEv) / exposureCurve;
	#endif

	return 1.0 - smoothstep(-8.0, -2.0, adaptedLogLuminance);
}

vec3 ScotopicVision(vec3 color, float mesopicFactor) {
	const vec3 photopicResponse = vec3(0.2627002, 0.6779981, 0.0593017);
	// Normalized from Ys = -0.702 X + 1.039 Y + 0.433 Z.
	const vec3 scotopicResponse = vec3(-0.2065580, 0.7293298, 0.4772282);

	float photopicLuminance = max0(dot(color, photopicResponse));
	float scotopicLuminance = max0(dot(color, scotopicResponse));

	#ifdef PURKINJE_SHIFT_NOISE
		scotopicLuminance *= 0.5 + SampleStbnVec1(ivec2(gl_FragCoord.xy), frameCounter);
	#endif

	float localFactor = rcp(1.0 + 2.0 * photopicLuminance);
	float rodWeight = saturate(PURKINJE_SHIFT_STRENGTH * mesopicFactor * localFactor);

	float rodLuminance = min(scotopicLuminance, 2.0 * photopicLuminance);
	return mix(color, vec3(rodLuminance), rodWeight);
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
	#define REAL_TONE_MAPPER HDR_TONE_MAPPER
#else
	#define REAL_TONE_MAPPER TONE_MAPPER
#endif

#if REAL_TONE_MAPPER == 1
	#define TONEMAPPING_FN AgX_Minimal
#elif REAL_TONE_MAPPER == 2
	#define TONEMAPPING_FN AgX_Full
#elif REAL_TONE_MAPPER == 3
    #define TONEMAPPING_FN AgX_AllenWp
#elif REAL_TONE_MAPPER == 16
	#define TONEMAPPING_FN AcademyFit
#elif REAL_TONE_MAPPER == 17
	#define TONEMAPPING_FN ACES2
#elif REAL_TONE_MAPPER == 32
	#define TONEMAPPING_FN GT
#elif REAL_TONE_MAPPER == 33
	#define TONEMAPPING_FN GT7
#elif REAL_TONE_MAPPER == 48
	#define TONEMAPPING_FN Lottes
#else
	#define TONEMAPPING_FN None
#endif

//======// Main //================================================================================//
void main() {
    // When super resolution is enabled, texelPos will be at the original resolution
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = texelToUv(texelPos);

	#if EXPOSURE_MODE == MANUAL
		float exposure = exp2(-MANUAL_EV);
	#else
		float exposure = exposure.value;
	#endif

    #ifdef MOTION_BLUR
        color = texelFetch(colortex0, texelPos, 0).rgb;
    #else
        color = texelFetch(colortex1, texelPos, 0).rgb;
    #endif

	// Bloom and fog
	#ifdef BLOOM
		CombineBloomAndFog(color, screenCoord, exposure);
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
		float mesopicFactor = MesopicAdaptation(exposure);
		color = ScotopicVision(color, mesopicFactor);
	#endif

	// Vignetting
	#ifdef VIGNETTE_ENABLED
        vec2 ndcCoord = screenCoord * 2.0 - 1.0;
		ndcCoord.x *= mix(1.0, aspectRatio, VIGNETTE_ROUNDNESS);
		color *= exp2(-0.5 * VIGNETTE_STRENGTH * sdot(ndcCoord));
	#endif

    // Tone mapping
    color = TONEMAPPING_FN(color);

    // Contrast
    #if COLOR_CONTRAST != 100
        const float contrast = COLOR_CONTRAST / 100.0;
        float luminanceIn = luminance(color);
        float luminanceOut = max0(contrast * (luminanceIn - 0.18) + 0.18);
        color *= luminanceOut / maxEps(luminanceIn);
    #endif

    // Saturation
    #if COLOR_SATURATION != 100
        const float saturation = COLOR_SATURATION / 100.0;
        color = max0(mix(vec3(luminance(color)), color, saturation));
    #endif

    #ifndef HDR_ENABLED
        // Working to display space
        color *= Rec2020_2_sRGB;

        // Gamma correction
        color = saturate(pow(color, vec3(1.0 / GAMMA_CORRECTION)));
    #else
        // Limited in Rec2020 non negative linear value range for CAS
        color = max0(color);
    #endif

	// Debug tone mapping plot
	#ifdef DEBUG_TONE_MAPPING_PLOT
		const float scale = 1.5;

        vec2 uv = screenCoord * vec2(aspectRatio, 1.0) * scale;
        float plot = smoothstep(0.0, scale * scaledPixelSize.y, abs(screenCoord.y - TONEMAPPING_FN(vec3(uv.x)).x));

		// Show LDR range
		color = vec3(0.25) * step(uv.x, 1.0);
		color = mix(vec3(1.0), color, plot);
	#endif
}
