// https://github.com/aces-aswf/aces-core

/*
The following are the license terms for ACES 1
--------------------------------------------------------------------------------
	# License Terms for Academy Color Encoding System Components #

	Academy Color Encoding System (ACES) software and tools are provided by the
	Academy under the following terms and conditions: A worldwide, royalty-free,
	non-exclusive right to copy, modify, create derivatives, and use, in source and
	binary forms, is hereby granted, subject to acceptance of this license.

	Copyright © 2015 Academy of Motion Picture Arts and Sciences (A.M.P.A.S.).
	Portions contributed by others as indicated. All rights reserved.

	Performance of any of the aforementioned acts indicates acceptance to be bound
	by the following terms and conditions:

	* Copies of source code, in whole or in part, must retain the above copyright
	notice, this list of conditions and the Disclaimer of Warranty.

	* Use in binary form must retain the above copyright notice, this list of
	conditions and the Disclaimer of Warranty in the documentation and/or other
	materials provided with the distribution.

	* Nothing in this license shall be deemed to grant any rights to trademarks,
	copyrights, patents, trade secrets or any other intellectual property of
	A.M.P.A.S. or any contributors, except as expressly stated herein.

	* Neither the name "A.M.P.A.S." nor the name of any other contributors to this
	software may be used to endorse or promote products derivative of or based on
	this software without express prior written permission of A.M.P.A.S. or the
	contributors, as appropriate.

	This license shall be construed pursuant to the laws of the State of
	California, and any disputes related thereto shall be subject to the
	jurisdiction of the courts therein.

	Disclaimer of Warranty: THIS SOFTWARE IS PROVIDED BY A.M.P.A.S. AND CONTRIBUTORS
	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
	THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
	NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL A.M.P.A.S., OR ANY
	CONTRIBUTORS OR DISTRIBUTORS, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, RESITUTIONARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
	LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
	PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
	LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
	OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
	ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	WITHOUT LIMITING THE GENERALITY OF THE FOREGOING, THE ACADEMY SPECIFICALLY
	DISCLAIMS ANY REPRESENTATIONS OR WARRANTIES WHATSOEVER RELATED TO PATENT OR
	OTHER INTELLECTUAL PROPERTY RIGHTS IN THE ACADEMY COLOR ENCODING SYSTEM, OR
	APPLICATIONS THEREOF, HELD BY PARTIES OTHER THAN A.M.P.A.S.,WHETHER DISCLOSED OR
	UNDISCLOSED.
--------------------------------------------------------------------------------
*/

float rgbToSaturation(vec3 rgb) {
	float minC = min(min(rgb.r, rgb.g), rgb.b);
	float maxC = max(max(rgb.r, rgb.g), rgb.b);

	return (max(maxC, 1e-10) - max(minC, 1e-10)) / max(maxC, 1e-2);
}

// Returns a geometric hue angle in degrees (0-360) based on RGB values
// For neutral colors, hue is undefined and the function will return zero (The reference
// implementation returns NaN but I think that's silly)
float rgbToHue(vec3 rgb) {
	if (rgb.r == rgb.g && rgb.g == rgb.b) return 0.0;

	float hue = (360.0 / TAU) * atan(2.0 * rgb.r - rgb.g - rgb.b, sqrt(3.0) * (rgb.g - rgb.b));

	if (hue < 0.0) hue += 360.0;

	return hue;
}

// Converts RGB to a luminance proxy, here called YC
// YC is ~ Y + K * Chroma
float rgbToYc(vec3 rgb) {
	const float yc_radius_weight = 1.75;

	float chroma = sqrt(rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b));

	return (rgb.r + rgb.g + rgb.b + yc_radius_weight * chroma) * rcp(3.0);
}

const mat3 Rec2020_2_AP0 = mat3(
	0.6790856347, 0.1577009146, 0.1632134507,
	0.0460020031, 0.8590546730, 0.0949433240,
	-0.0005739432, 0.0284677684, 0.9721061748
);

const mat3 Rec2020_2_AP1 = mat3(
	0.9748949779, 0.0195991086, 0.0055059134,
	0.0021795628, 0.9955354689, 0.0022849683,
	0.0047972397, 0.0245320166, 0.9706707437
);

const mat3 AP0_2_Rec2020 = mat3(
	1.4904095205, -0.2661709193, -0.2242386013,
	-0.0801674998,  1.1821671211, -0.1019996212,
	0.0032276312, -0.0347764757,  1.0315488446
);

const mat3 AP1_2_Rec2020 = mat3(
	1.0258247477, -0.0200531908, -0.0057715568,
	-0.0022343695,  1.0045865019, -0.0023521324,
	-0.0050133515, -0.0252900718,  1.0303034233
);

const mat3 AP0_2_XYZ = mat3(
	0.9525523959,  0.0000000000,  0.0000936786,
	0.3439664498,  0.7281660966, -0.0721325464,
	0.0000000000,  0.0000000000,  1.0088251844
);
const mat3 XYZ_2_AP0 = mat3(
	1.0498110175,  0.0000000000, -0.0000974845,
	-0.4959030231,  1.3733130458,  0.0982400361,
	0.0000000000,  0.0000000000,  0.9912520182
);

const mat3 AP1_2_XYZ = mat3(
	0.6624541811,  0.1340042065,  0.1561876870,
	0.2722287168,  0.6740817658,  0.0536895174,
	-0.0055746495,  0.0040607335,  1.0103391003
);
const mat3 XYZ_2_AP1 = mat3(
	1.6410233797, -0.3248032942, -0.2364246952,
	-0.6636628587,  1.6153315917,  0.0167563477,
	0.0117218943, -0.0082844420,  0.9883948585
);

const mat3 AP0_2_AP1 = AP0_2_XYZ * XYZ_2_AP1;
const mat3 AP1_2_AP0 = AP1_2_XYZ * XYZ_2_AP0;

const mat3 sRGB_2_AP0 = sRGB_2_XYZ * XYZ_2_AP0;
const mat3 AP0_2_sRGB = AP0_2_XYZ * XYZ_2_sRGB;

const mat3 sRGB_2_AP1 = sRGB_2_XYZ * XYZ_2_AP1;
const mat3 AP1_2_sRGB = AP1_2_XYZ * XYZ_2_sRGB;

const mat3 D60ToD65_CAT = mat3(
	0.98722400, -0.00611327, 0.01595330,
	-0.00759836,  1.00186000, 0.00533002,
	0.00307257, -0.00509595, 1.08168000
);

const vec3 AP1_RGB2Y = vec3(0.2722287168, 0.6740817658, 0.0536895174);

//======// ACES 1 Fit //============================================================================//
// "Glow" module constants
const float rrtGlowGain  = 0.05;   	// Default: 0.05
const float rrtGlowMid   = 0.08;   	// Default: 0.08

// Red modifier constants
const float rrtRedScale  = 0.82;  	// Default: 0.82
const float rrtRedPivot  = 0.03;    // Default: 0.03
const float rrtRedHue    = 0.0;     // Default: 0.0
const float rrtRedWidth  = 135.0; 	// Default: 135.0

// Desaturation contants
const float rrtSatFactor = 0.96; 	// Default: 0.96
const float odtSatFactor = 0.93; 	// Default: 0.93

// ------- Glow module functions
float GlowFwd(float yc_in, float glow_gain_in, const float glow_mid) {
	float glow_gain_out;

	if (yc_in <= 2.0 / 3.0 * glow_mid) {
		glow_gain_out = glow_gain_in;
	} else if (yc_in >= 2.0 * glow_mid) {
		glow_gain_out = 0.0;
	} else {
		glow_gain_out = glow_gain_in * (glow_mid / yc_in - 0.5);
	}

	return glow_gain_out;
}

float SigmoidShaper(float x) {
	// Sigmoid function in the range 0 to 1 spanning -2 to +2
	float t = max0(1.0 - abs(0.5 * x));
	float y = 1.0 + signMul(oms(t * t), x);

	return 0.5 * y;
}

// ------- Red modifier functions
float CubicBasisShaper(float x, float w) {
	const mat4 M = mat4(
		-1.0 / 6.0,  3.0 / 6.0, -3.0 / 6.0,  1.0 / 6.0,
		3.0 / 6.0, -6.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0,
		-3.0 / 6.0,  0.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0,
		1.0 / 6.0,  4.0 / 6.0,  1.0 / 6.0,  0.0 / 6.0
	);

	float knots[5] = float[5](
		w * -0.5,
		w * -0.25,
		0.0,
		w *  0.25,
		w *  0.5
	);

	float y = 0;
	if ((x > knots[0]) && (x < knots[4])) {
		float knot_coord = (x - knots[0]) * 4.0 / w;
		int j = int(knot_coord);
		float t = knot_coord - j;

		vec4 monomials = vec4(cube(t), sqr(t), t, 1.0);

		switch(j) {
			case 3:  y = monomials[0] * M[0][0] + monomials[1] * M[1][0] + monomials[2] * M[2][0] + monomials[3] * M[3][0]; break;
			case 2:  y = monomials[0] * M[0][1] + monomials[1] * M[1][1] + monomials[2] * M[2][1] + monomials[3] * M[3][1]; break;
			case 1:  y = monomials[0] * M[0][2] + monomials[1] * M[1][2] + monomials[2] * M[2][2] + monomials[3] * M[3][2]; break;
			case 0:  y = monomials[0] * M[0][3] + monomials[1] * M[1][3] + monomials[2] * M[2][3] + monomials[3] * M[3][3]; break;
			default: y = 0.0; break;
		}
	}

	return y * 1.5;
}

// https://github.com/sixthsurge/photon/blob/main/shaders/include/aces/aces.glsl
float CubicBasisShaperFit(float x, const float width) {
	float radius = 0.5 * width;
	return abs(x) < radius ? sqr(hermite(1.0 - abs(x) / radius)) : 0.0;
}

float CenterHue(float hue, float centerH) {
	float hueCentered = hue - centerH;
	if (hueCentered < -180.0) hueCentered += 360.0;
	else if (hueCentered > 180.0) hueCentered -= 360.0;
	return hueCentered;
}

#define log10(x) (log2(x) * rcp(log2(10.0)))

vec3 RRTSweeteners(vec3 aces) {
	// --- Glow module --- //
	float saturation = rgbToSaturation(aces);
	float ycIn = rgbToYc(aces);
	float s = SigmoidShaper(saturation * 5.0 - 2.0);
	float addedGlow = 1.0 + GlowFwd(ycIn, rrtGlowGain * s, rrtGlowMid);

	aces *= addedGlow;

	// --- Red modifier --- //
	float hue = rgbToHue(aces);
	float centeredHue = CenterHue(hue, rrtRedHue);
	float hueWeight = CubicBasisShaperFit(centeredHue, rrtRedWidth);

	aces.r += hueWeight * saturation * (rrtRedPivot - aces.r) * oms(rrtRedScale);

	// --- ACES to RGB rendering space --- //
	vec3 rgbPre = max0(aces * AP0_2_AP1);

	// --- Global desaturation --- //
	rgbPre = mix(vec3(dot(rgbPre, AP1_RGB2Y)), rgbPre, rrtSatFactor);

	return rgbPre;
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 RRTAndODTFit(vec3 rgb) {
	vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
	vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;

	return a / b;
}

#ifndef HDR_ENABLED
	vec3 AcademyFit(vec3 rgb) {
        rgb *= 1.5; // Match other tonemappers' exposure
		rgb *= Rec2020_2_AP0;

		// Apply RRT sweeteners
		rgb = RRTSweeteners(rgb);

		// Apply RRT and ODT
		rgb = RRTAndODTFit(rgb);

		// Global desaturation
		rgb = mix(vec3(dot(rgb, AP1_RGB2Y)), rgb, odtSatFactor);

		return rgb * AP1_2_Rec2020;
	}
#else
	// Use this simpler fit for HDR as of now.
	// https://knarkowicz.wordpress.com/2016/08/31/hdr-display-first-steps/
	vec3 AcademyFit(vec3 x) {
		x *= 0.65;
		const float a = 15.8f;
		const float b = 2.12f;
		const float c = 1.2f;
		const float d = 5.92f;
		const float e = 1.9f;
		return ( x * ( a * x + b ) ) / ( x * ( c * x + d ) + e );
	}
#endif

//======// ACES 2.0 //===========================================================================//

// This implementation is based on the shaders emitted by OCIO's ACES 2.0 implementation and [the reference implementation](https://github.com/aces-aswf/aces-core)
// ACES 2.0 is licensed under Apache License 2.0. You can find a copy in the root of this repository(/LICENSE).
// Copyright Contributors to the ACES Project.
/*
	Copyright Contributors to the OpenColorIO Project.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are
	met:

	* Redistributions of source code must retain the above copyright
	notice, this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright
	notice, this list of conditions and the following disclaimer in the
	documentation and/or other materials provided with the distribution.
	* Neither the name of the copyright holder nor the names of its
	contributors may be used to endorse or promote products derived from
	this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
	A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
	HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
	LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
	DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
	THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

layout(r32f) readonly uniform image1D acesReachMTable;
layout(rgba32f) readonly uniform image1D acesGamutCuspTable;

float aces_reach_m_table_sample(float h) {
	float i_base = floor(h);
	float i_lo = i_base + 1;
	float i_hi = i_lo + 1;
    float lo = imageLoad(acesReachMTable, int(i_lo)).r;
    float hi = imageLoad(acesReachMTable, int(i_hi)).r;
	float t = h - i_base;
	return mix(lo, hi, t);
}

float aces_tonescale_fwd0(float J) {
	float A = 0.0323680267 * pow(abs(J) * 0.00999999978, 0.879464149);
	float Y = pow((27.1299992 * A) / (1.0 - A), 2.3809523809523809);
	#ifndef HDR_ENABLED
		float f = 1.04710376 * pow(Y / (Y + 0.73009213709383403), 1.14999998);
	#else
		float f = 41.1687241 * pow(Y / (Y + 14.433662900070772), 1.14999998);
	#endif
	float Y_ts = max0(f * f / (f + 0.0399999991));
	float F_L_Y = pow(0.79370057210326195 * Y_ts, 0.42);
	float J_ts = 100.0 * pow((F_L_Y / (27.1299992 + F_L_Y)) * 30.8946857, 1.13705599);
	return sign(J) * J_ts;
}

float aces_toe_fwd0(float x, float limit, float k1_in, float k2_in) {
	float k2 = max(k2_in, 0.001);
	float k1 = sqrt(k1_in * k1_in + k2 * k2);
	float k3 = (limit + k1) / (limit + k2);
	return (x > limit) ? x : 0.5 * (k3 * x - k1 + sqrt((k3 * x - k1) * (k3 * x - k1) + 4.0 * k2 * k3 * x));
}

vec3 aces_gamut_cusp_table_sample(float h) {
	int i = int(h) + 1;
	int i_lo = int(max(float(0), float(i + 0)));
	int i_hi = int(min(float(361), float(i + 2)));
	while (i_lo + 1 < i_hi) {
		float hcur = aces_gamut_cusp_table_hues_array[i];
		if (h > hcur) {
			i_lo = i;
		} else {
			i_hi = i;
		}
		i = (i_lo + i_hi) >> 1;
	}
    vec3 lo = imageLoad(acesGamutCuspTable, int(i_hi - 1)).rgb;
    vec3 hi = imageLoad(acesGamutCuspTable, int(i_hi)).rgb;
	float t = (h - aces_gamut_cusp_table_hues_array[i_hi - 1]) / (aces_gamut_cusp_table_hues_array[i_hi] - aces_gamut_cusp_table_hues_array[i_hi - 1]);
	return mix(lo, hi, t);
}

float aces_get_focus_gain0(float J, float cuspJ) {
	float thr = mix(cuspJ, aces_limit_J_max, 0.300000);
	if (J > thr) {
		float gain = (aces_limit_J_max - thr) / maxEps(aces_limit_J_max - J);
		gain = log10(gain);
		return gain * gain + 1.0;
	} else {
		return 1.0;
	}
}

float aces_solve_J_intersect0(float J, float M, float focusJ, float slope_gain) {
	float M_scaled = M / slope_gain;
	float a = M_scaled / focusJ;
	if (J < focusJ) {
		float b = 1.0 - M_scaled;
		float c = -J;
		float det = b * b - 4.0 * a * c;
		float root = sqrt(det);
		return -2.0 * c / (b + root);
	} else {
		float b = -(1.0 + M_scaled + aces_limit_J_max * a);
		float c = aces_limit_J_max * M_scaled + J;
		float det = b * b - 4.0 * a * c;
		float root = sqrt(det);
		return -2.0 * c / (b - root);
	}
}

float aces_find_gamut_boundary_intersection0(vec2 JM_cusp, float gamma_top_inv, float gamma_bottom_inv, float J_intersect_source, float J_intersect_cusp, float slope) {
	float M_boundary_lower = J_intersect_cusp * pow(J_intersect_source / J_intersect_cusp, gamma_bottom_inv) / (JM_cusp.r / JM_cusp.g - slope);
	float M_boundary_upper = JM_cusp.g * (aces_limit_J_max - J_intersect_cusp) * pow((aces_limit_J_max - J_intersect_source) / (aces_limit_J_max - J_intersect_cusp), gamma_top_inv) / (slope * JM_cusp.g + aces_limit_J_max - JM_cusp.r);
	float smin = 0.0;
	{
		float a = M_boundary_lower > 0.0 ? M_boundary_lower : 10000.0;
		float b = M_boundary_upper > 0.0 ? M_boundary_upper : 10000.0;
		float s = 0.119999997 * JM_cusp.g;
		float h = max0(s - abs(a - b)) / s;
		smin = min(a, b) - h * h * h * s * 0.16666666666666666;
	}
	return smin;
}

float aces_remap_M_fwd0(float M, float gamut_boundary_M, float reach_boundary_M) {
	float boundary_ratio = gamut_boundary_M / reach_boundary_M;
	float proportion = max(boundary_ratio, 0.75);
	float threshold = proportion * gamut_boundary_M;
	if (proportion >= 1.0 || M <= threshold) {
		return M;
	}
	float m_offset = M - threshold;
	float gamut_offset = gamut_boundary_M - threshold;
	float reach_offset = reach_boundary_M - threshold;
	float scale = reach_offset / ((reach_offset / gamut_offset) - 1.0);
	float nd = m_offset / scale;
	return threshold + scale * nd / (1.0 + nd);
}

vec3 aces_gamut_compress0(vec3 JMh, float Jx, vec3 JMGcusp, float reachMaxM) {
	float J = JMh.r;
	float M = JMh.g;
	float h = JMh.b;
	if (J < EPS) {
		return vec3(0.0, 0.0, h);
	}
	if (M < EPS || J > aces_limit_J_max) {
		return vec3(J, 0.0, h);
	} else {
		vec2 JMcusp = JMGcusp.rg;
		float focusJ = mix(JMcusp.r, 34.096539, min(1.0, 1.300000 - (JMcusp.r / aces_limit_J_max)));
		float slope_gain = 135.0 * aces_get_focus_gain0(Jx, JMcusp.r);
		float J_intersect_source = aces_solve_J_intersect0(JMh.r, JMh.g, focusJ, slope_gain);
		float gamut_slope = (J_intersect_source < focusJ) ? J_intersect_source : (aces_limit_J_max - J_intersect_source);
		gamut_slope = gamut_slope * (J_intersect_source - focusJ) / (focusJ * slope_gain);
		float gamma_top_inv = JMGcusp.b;
		float gamma_bottom_inv = 0.877192974;
		float J_intersect_cusp = aces_solve_J_intersect0(JMcusp.r, JMcusp.g, focusJ, slope_gain);
		float gamutBoundaryM = aces_find_gamut_boundary_intersection0(JMcusp, gamma_top_inv, gamma_bottom_inv, J_intersect_source, J_intersect_cusp, gamut_slope);
		if (gamutBoundaryM < EPS) {
			return vec3(J, 0.0, h);
		}
		float reachBoundaryM = aces_limit_J_max * pow(J_intersect_source / aces_limit_J_max, 0.879464149);
		reachBoundaryM = reachBoundaryM / ((aces_limit_J_max / reachMaxM) - gamut_slope);
		float remapped_M = aces_remap_M_fwd0(M, gamutBoundaryM, reachBoundaryM);
		float remapped_J = J_intersect_source + remapped_M * gamut_slope;
		return vec3(remapped_J, remapped_M, h);
	}
}

vec3 ACES2(vec3 inPixel) {
    inPixel *= 2.0; // Match other tonemappers' exposure
	vec3 outColor = inPixel * Rec2020_2_AP1;

	outColor = RGB_to_JMh(outColor);
	float h_rad = outColor.b * 0.0174532924;
	float cos_hr = cos(h_rad);
	float sin_hr = sin(h_rad);

	// ToneScale and ChromaCompress (fwd)

	float J_ts = aces_tonescale_fwd0(outColor.r);
	// Sample tables (fwd)
	float reachMaxM = aces_reach_m_table_sample(outColor.b);

	float J = outColor.r;
	float M = outColor.g;
	float h = outColor.b;
	float M_cp = M;
	if (M != 0.0) {
		float nJ = J_ts / aces_limit_J_max;
		float snJ = max0(1.0 - nJ);
		float Mnorm;

		float cos_hr2 = 2.0 * cos_hr * cos_hr - 1.0;
		float sin_hr2 = 2.0 * cos_hr * sin_hr;
		float cos_hr3 = 4.0 * cos_hr * cos_hr * cos_hr - 3.0 * cos_hr;
		float sin_hr3 = 3.0 * sin_hr - 4.0 * sin_hr * sin_hr * sin_hr;
		vec3 cosines = vec3(cos_hr, cos_hr2, cos_hr3);
		vec3 cosine_weights = vec3(11.341321604032515, 16.469863649185896, 7.8842182208776475);
		vec3 sines = vec3(sin_hr, sin_hr2, sin_hr3);
		vec3 sine_weights = vec3(14.665187919584513, -6.3725780354404442, 9.1941277054452897);
		Mnorm = dot(cosines, cosine_weights) + dot(sines, sine_weights) + 77.133051547393805;

		float limit = pow(nJ, 0.879464149) * reachMaxM / Mnorm;
		M_cp = M * pow(J_ts / J, 0.879464149);
		M_cp = M_cp / Mnorm;
		M_cp = limit - aces_toe_fwd0(limit - M_cp, limit - 0.001, snJ * 1.29999995, sqrt(nJ * nJ + 0.00499999989));
		M_cp = aces_toe_fwd0(M_cp, limit, nJ * 2.4000001, snJ);
		M_cp = M_cp * Mnorm;
	}
	outColor.rgb = vec3(J_ts, M_cp, h);

	// GamutCompress (fwd)

	#if defined(HDR_ENABLED) && ACES_HDR_TARGET_GAMUT != 0
		vec3 JMGcusp = aces_gamut_cusp_table_sample(outColor.b);
		outColor.rgb = aces_gamut_compress0(outColor.rgb, outColor.r, JMGcusp, reachMaxM);
	#endif

	outColor = JMh_to_RGB(outColor);

	#ifndef HDR_ENABLED
		outColor = saturate(outColor) * sRGB_2_Rec2020;
	#elif ACES_HDR_TARGET_GAMUT == 2
		// P3-D65 to Rec.2020
		outColor = mat3(0.75383303436172167, 0.045743848965358269, -0.0012103403545183939, 0.1985973690526166, 0.94177721981169349, 0.01760171730109, 0.047569596585661789, 0.012478931222948141, 0.98360862305342855) * outColor;
	#endif

	return outColor;
}
