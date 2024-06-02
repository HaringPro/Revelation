
/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

#define TONEMAP AcademyFit // [AcademyFit AcademyFull AgX_Minimal AgX_Full Uchimura Lottes]

//======// Output //==============================================================================//

/* RENDERTARGETS: 3 */
layout(location = 0) out vec3 LDRImageOut;

//======// Input //===============================================================================//

//======// Uniform //=============================================================================//

uniform sampler2D colortex0;
uniform sampler2D colortex1;

uniform vec2 viewPixelSize;

//======// Function //============================================================================//

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
    ivec2 texel = ivec2(gl_FragCoord.xy);

	vec3 HDRImage = texelFetch(colortex1, texel, 0).rgb;

	// LDRImageOut = linearToSRGB(HDRImage);
	LDRImageOut = TONEMAP(HDRImage);

	LDRImageOut = saturate(LDRImageOut);
}
