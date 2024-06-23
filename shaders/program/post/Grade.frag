/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Combine bloom and fog, apply exposure, color grading and etc.

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.glsl"

#define TONEMAP_OPERATOR AgX_Minimal // [None AcademyFit AcademyFull AgX_Minimal AgX_Full Uchimura Lottes]

#define BLOOM_INTENSITY 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]

#define PURKINJE_SHIFT // Enable purkinje shift effect
#define PURKINJE_SHIFT_STRENGTH 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

//======// Output //==============================================================================//

/* RENDERTARGETS: 8 */
layout (location = 0) out vec3 LDRImageOut;

//======// Input //===============================================================================//

flat in float exposure;

//======// Uniform //=============================================================================//

uniform sampler2D colortex0; // Bloom tiles
uniform sampler2D colortex1; // HDR scene image
uniform sampler2D colortex3; // Rain alpha
uniform sampler2D colortex6; // Bloomy fog transmittance

uniform float aspectRatio;
uniform float wetnessCustom;

uniform vec2 viewPixelSize;

//======// Function //============================================================================//

vec2 CalculateTileOffset(in const int lod) {
	vec2 lodMult = floor(lod * 0.5 + vec2(0.0, 0.5));
	vec2 offset = vec2(1.0 / 3.0, 2.0 / 3.0) * (1.0 - exp2(-2.0 * lodMult));

	return lodMult * 12.0 * viewPixelSize + offset;
}

vec3 BloomTileUpsample(in vec2 screenCoord, in const int lod) {
    vec2 coord = screenCoord * exp2(-float(lod + 1)) + CalculateTileOffset(lod);

    return textureBicubic(colortex0, coord).rgb;
}

void CombineBloomAndFog(inout vec3 image, in ivec2 texel) {
	vec3 bloomData = vec3(0.0);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	float weight = 1.0;
	float sumWeight = 0.0;

	for (int i = 0; i < 7; ++i) {
		vec3 sampleTile = BloomTileUpsample(screenCoord, i);

		bloomData += sampleTile * weight;
		sumWeight += weight;
		weight *= 0.9;
	}

	bloomData /= sumWeight;

	float bloomIntensity = BLOOM_INTENSITY * 0.08;
	bloomIntensity *= fma(1.0 / max(exposure, 1.0), 0.7, 0.3);

	image = mix(image, bloomData, bloomIntensity);

	#ifdef BLOOMY_FOG
		float fogTransmittance = texelFetch(colortex6, texel, 0).x;

		image = mix(bloomData, image, saturate(fogTransmittance));
	#endif

	if (wetnessCustom > 1e-2) {
		float rain = texelFetch(colortex3, texel, 0).x * RAIN_VISIBILITY;
		image = image * oneMinus(rain) + bloomData * rain;
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

// https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 Lottes(in vec3 x) {
	x *= 2.0;

	const vec3 a      = vec3(1.3);
	const vec3 d      = vec3(0.95);
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

	vec3 HDRImage = texelFetch(colortex1, screenTexel, 0).rgb;

	// Bloom and fog
	#ifdef BLOOM_ENABLED
		CombineBloomAndFog(HDRImage, screenTexel);
	#endif

	// Purkinje shift
	#ifdef PURKINJE_SHIFT
		float luma = dot(HDRImage, vec3(0.25, 0.4, 0.35));
		float purkinjeFactor = exp2(-2e2 / PURKINJE_SHIFT_STRENGTH * luma) * exposure / (exposure + 1.0);
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

	// Tone mapping
	LDRImageOut = TONEMAP_OPERATOR(HDRImage);

	// LDR range clamp
	LDRImageOut = saturate(LDRImageOut);
}
