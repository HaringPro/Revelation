/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Combine bloom and fog, apply exposure, color-grading, vignetting, etc.

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define TONEMAP_OPERATOR AgX_Minimal // [None AcademyFit AcademyFull AgX_Minimal AgX_Full Uchimura Lottes]

#define BLOOM_INTENSITY 1.0 // Intensity of bloom. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]
#define BLOOMY_FOG_INTENSITY 0.75 // Intensity of bloomy fog. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

#define PURKINJE_SHIFT // Enables purkinje shift effect
#define PURKINJE_SHIFT_STRENGTH 0.4 // Strength of purkinje shift effect. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // Strength of vignetting effect. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // Roundness of vignetting effect. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

//======// Output //==============================================================================//

/* RENDERTARGETS: 8 */
layout (location = 0) out vec3 LDRImageOut;

//======// Input //===============================================================================//

flat in float exposure;

//======// Uniform //=============================================================================//

#ifdef MOTION_BLUR
	uniform sampler2D colortex0; // Motion blur output
#else
	uniform sampler2D colortex1; // TAA output
#endif
uniform sampler2D colortex4; // Bloom tiles
uniform sampler2D colortex5; // Sky-View LUT
uniform sampler2D colortex6; // Rain alpha
uniform sampler2D colortex8; // Bloomy fog transmittance

uniform float aspectRatio;
uniform float rainStrength;

uniform vec2 viewPixelSize;

//======// Function //============================================================================//

const vec2 bloomTileOffset[7] = vec2[7](
	vec2(0.0000, 0.0000),
	vec2(0.0000, 0.5000),
	vec2(0.2500, 0.5000),
	vec2(0.2500, 0.6250),
	vec2(0.3125, 0.6250),
	vec2(0.3150, 0.6563),
	vec2(0.3281, 0.6563)
);

void CombineBloomAndFog(inout vec3 scene, in ivec2 texel) {
	vec3 bloomData = vec3(0.0);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	float weight = 1.0;
	float sumWeight = 0.0;

	for (int i = 0; i < 7; ++i) {
		screenCoord *= 0.5;
    	vec2 sampleCoord = screenCoord + bloomTileOffset[i] + viewPixelSize * float(i * 12);
		vec3 sampleTile = textureBicubic(colortex4, sampleCoord).rgb;

		bloomData += sampleTile * weight;
		sumWeight += weight;
		weight *= 0.9;
	}

	bloomData *= rcp(sumWeight);

	float bloomIntensity = BLOOM_INTENSITY * 0.075;
	bloomIntensity *= fma(1.0 / max(exposure, 1.0), 0.75, 0.25);

	scene = mix(scene, bloomData, bloomIntensity);

	#ifdef BLOOMY_FOG
		float fogTransmittance = texelFetch(colortex8, texel, 0).x;
		scene = mix(bloomData, scene, mix(1.0, saturate(fogTransmittance), BLOOMY_FOG_INTENSITY));
	#endif

	if (rainStrength > 1e-2) {
		float rain = texelFetch(colortex6, texel, 0).a * RAIN_VISIBILITY;
		scene = scene * oneMinus(rain) + bloomData * rain * 1.2;
	}
}

//================================================================================================//

const mat3 sRGBtoXYZ = mat3(
	vec3(0.4124564, 0.3575761, 0.1804375),
	vec3(0.2126729, 0.7151522, 0.0721750),
	vec3(0.0193339, 0.1191920, 0.9503041)
);

const mat3 XYZtoSRGB = mat3(
	vec3(3.2409699419, 	-1.5373831776, -0.4986107603),
	vec3(-0.9692436363,  1.8759675015,  0.0415550574),
	vec3(0.0556300797, 	-0.2039769589,  1.0569715142)
);

vec3 None(in vec3 x) {
	return linearToSRGB(x);
}

// Uchimura 2017, "HDR theory and practice"
// Math: https://www.desmos.com/calculator/gslcdxvipg
// Source: https://www.slideshare.net/nikuque/hdr-theory-and-practicce-jp
vec3 Uchimura(in vec3 x) {
    const float maxDisplayBrightness = 1.0;
    const float contrast			 = 1.0;
    const float linearStart			 = 0.2;
    const float linearLength		 = 0.1;
    const float black				 = 1.33;
    const float pedestal			 = 0.0;

    const float l0 = ((maxDisplayBrightness - linearStart) * linearLength) / contrast;
    const float L0 = linearStart - linearStart / contrast;
    const float L1 = linearStart + oneMinus(linearStart) / contrast;
    const float S0 = linearStart + l0;
    const float S1 = linearStart + contrast * l0;
    const float C2 = contrast * maxDisplayBrightness / (maxDisplayBrightness - S1);
    const float CP = -1.44269502 * C2 / maxDisplayBrightness;

    vec3 w0 = 1.0 - smoothstep(0.0, linearStart, x);
    vec3 w2 = step(S0, x);
    vec3 w1 = 1.0 - w0 - w2;

    vec3 T = pow(x, vec3(black)) / pow(linearStart, black - 1.0) + pedestal;
    vec3 S = maxDisplayBrightness - (maxDisplayBrightness - S1) * exp2(CP * (x - S0));
    vec3 L = linearStart + contrast * (x - linearStart);

    x = T * w0 + L * w1 + S * w2;

	return linearToSRGB(x);
}

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
// https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 Lottes(in vec3 x) {
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

	return pow(x, a) * (pow(hdrMax, ad) - pow(midIn, ad)) * midOut / (pow(x, ad) * b + c);
}

#include "/lib/post/ACES.glsl"
#include "/lib/post/AgX.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	#ifdef MOTION_BLUR
		vec3 HDRImage = texelFetch(colortex0, screenTexel, 0).rgb;
	#else
		vec3 HDRImage = texelFetch(colortex1, screenTexel, 0).rgb;
	#endif

	// Bloom and fog
	#ifdef BLOOM_ENABLED
		CombineBloomAndFog(HDRImage, screenTexel);
	#endif

	// Purkinje shift
	#ifdef PURKINJE_SHIFT
		float luma = dot(HDRImage, vec3(0.25, 0.4, 0.35));
		float purkinjeFactor = exp2(-4e2 / PURKINJE_SHIFT_STRENGTH * luma) * exposure / (exposure + 1.0);
		HDRImage = mix(HDRImage, vec3(0.7, 1.1, 1.5) * luma, purkinjeFactor);
	#endif

	// Exposure
	HDRImage *= exposure;

	// Vignetting
	#ifdef VIGNETTE_ENABLED
		vec2 clipCoord = gl_FragCoord.xy * viewPixelSize * 2.0 - 1.0;
		clipCoord.x *= mix(1.0, aspectRatio, VIGNETTE_ROUNDNESS);
		HDRImage *= fastExp(-0.4 * dotSelf(clipCoord) * VIGNETTE_STRENGTH);
	#endif

	// Debug sky-view
	#ifdef DEBUG_SKYVIEW
		HDRImage = texelFetch(colortex5, screenTexel >> 1, 0).rgb;
	#endif

	// Tone mapping
	LDRImageOut = TONEMAP_OPERATOR(HDRImage);
	// LDRImageOut = gl_FragCoord.x * viewPixelSize.x > 0.5 ? TONEMAP_OPERATOR(HDRImage) : None(HDRImage);

	// LDR range clamp
	LDRImageOut = saturate(LDRImageOut);
}