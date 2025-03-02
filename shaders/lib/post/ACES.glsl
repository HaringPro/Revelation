
// https://github.com/ampas/aces-dev/blob/dev

/*
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

float rgbToSaturation(in vec3 rgb) {
	return (max(maxOf(rgb), 1e-10) - max(minOf(rgb), 1e-10)) / max(maxOf(rgb), 1e-2);
}

// Returns a geometric hue angle in degrees (0-360) based on RGB values
// For neutral colors, hue is undefined and the function will return zero (The reference
// implementation returns NaN but I think that's silly)
float rgbToHue(in vec3 rgb) {
	if (rgb.r == rgb.g && rgb.g == rgb.b) return 0.0;

	float hue = (360.0 / TAU) * atan(2.0 * rgb.r - rgb.g - rgb.b, sqrt(3.0) * (rgb.g - rgb.b));

	if (hue < 0.0) hue += 360.0;

	return hue;
}

// Converts RGB to a luminance proxy, here called YC
// YC is ~ Y + K * Chroma
float rgbToYc(in vec3 rgb) {
	const float yc_radius_weight = 1.75;

	float chroma = sqrt(rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b));

	return (rgb.r + rgb.g + rgb.b + yc_radius_weight * chroma) / 3.0;
}

const mat3 AP0toXYZ = mat3(
	 0.9525523959,  0.0000000000,  0.0000936786,
	 0.3439664498,  0.7281660966, -0.0721325464,
	 0.0000000000,  0.0000000000,  1.0088251844
);
const mat3 XYZtoAP0 = mat3(
	 1.0498110175,  0.0000000000, -0.0000974845,
	-0.4959030231,  1.3733130458,  0.0982400361,
	 0.0000000000,  0.0000000000,  0.9912520182
);

const mat3 AP1toXYZ = mat3(
	 0.6624541811,  0.1340042065,  0.1561876870,
	 0.2722287168,  0.6740817658,  0.0536895174,
	-0.0055746495,  0.0040607335,  1.0103391003
);
const mat3 XYZtoAP1 = mat3(
	 1.6410233797, -0.3248032942, -0.2364246952,
	-0.6636628587,  1.6153315917,  0.0167563477,
	 0.0117218943, -0.0082844420,  0.9883948585
);

const mat3 AP0toAP1 = AP0toXYZ * XYZtoAP1;
const mat3 AP1toAP0 = AP1toXYZ * XYZtoAP0;

const mat3 D60ToD65_CAT = mat3(
     0.98722400, -0.00611327, 0.01595330,
    -0.00759836,  1.00186000, 0.00533002,
     0.00307257, -0.00509595, 1.08168000
);

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
const float odtSatFactor = 1.0; 	// Default: 0.93

// ------- Glow module functions
float GlowFwd(in float yc_in, in float glow_gain_in, in const float glow_mid) {
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

float SigmoidShaper(in float x) {
	// Sigmoid function in the range 0 to 1 spanning -2 to +2
	float t = max0(1.0 - abs(0.5 * x));
	float y = 1.0 + fastSign(x) * oneMinus(t * t);

	return 0.5 * y;
}

// ------- Red modifier functions
float CubicBasisShaper(in float x, in float w) {
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
float CubicBasisShaperFit(in float x, in const float width) {
	float radius = 0.5 * width;
	return abs(x) < radius ? sqr(curve(1.0 - abs(x) / radius)) : 0.0;
}

float CenterHue(in float hue, in float centerH) {
	float hueCentered = hue - centerH;
	if (hueCentered < -180.0) hueCentered += 360.0;
	else if (hueCentered > 180.0) hueCentered -= 360.0;
	return hueCentered;
}

//======// ACES Fit //============================================================================//

vec3 RRTSweeteners(in vec3 aces) {
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

	aces.r += hueWeight * saturation * (rrtRedPivot - aces.r) * oneMinus(rrtRedScale);

    // --- ACES to RGB rendering space --- //
    aces = satU16f(aces);
	vec3 rgbPre = satU16f(aces * AP0toAP1);

	// --- Global desaturation --- //
	float luminance = luminance(rgbPre);
	rgbPre = mix(vec3(luminance), rgbPre, rrtSatFactor);

	return rgbPre;
}


#define log10(x) (log(x) * rcp(log(10.0)))

// Textbook monomial to basis-function conversion matrix
const mat3 M = mat3(
	 0.5, -1.0,  0.5,
	-1.0,  1.0,  0.5,
	 0.5,  0.0,  0.0
);

struct SegmentedSplineParams_c5 {
    float coeffsLow[6];     // Coeffs for B-spline between minPoint and midPoint (units of log luminance)
    float coeffsHigh[6];    // Coeffs for B-spline between midPoint and maxPoint (units of log luminance)
    vec2 minPoint;          // {luminance, luminance} Linear extension below this
    vec2 midPoint;          // {luminance, luminance} Linear
    vec2 maxPoint;          // {luminance, luminance} Linear extension above this
    float slopeLow;         // Log-log slope of low linear extension
    float slopeHigh;        // Log-log slope of high linear extension
};

struct SegmentedSplineParams_c9 {
    float coeffsLow[10];    // Coeffs for B-spline between minPoint and midPoint (units of log luminance)
    float coeffsHigh[10];   // Coeffs for B-spline between midPoint and maxPoint (units of log luminance)
    vec2 minPoint;          // {luminance, luminance} Linear extension below this
    vec2 midPoint;          // {luminance, luminance} Linear
    vec2 maxPoint;          // {luminance, luminance} Linear extension above this
    float slopeLow;         // Log-log slope of low linear extension
    float slopeHigh;        // Log-log slope of high linear extension
};

const SegmentedSplineParams_c5 RRT_PARAMS = SegmentedSplineParams_c5(
    float[6] ( -4.0000000000, -4.0000000000, -3.1573765773, -0.4852499958, 1.8477324706, 1.8477324706 ),    // coeffsLow
    float[6] ( -0.7185482425, 2.0810307172, 3.6681241237, 4.0000000000, 4.0000000000, 4.0000000000 ),       // coeffsHigh
    vec2(0.18 * exp2(-15.0), 0.0001),   // minPoint
    vec2(0.18, 4.8),                    // midPoint
    vec2(0.18 * exp2( 18.0), 10000.0),  // maxPoint
    0.0,    // slopeLow
    0.0     // slopeHigh
);

float segmented_spline_c5_fwd(float x, SegmentedSplineParams_c5 params) { // params should default to RRT_PARAMS
    const int N_KNOTS_LOW  = 4;
    const int N_KNOTS_HIGH = 4;

    float logMinPoint = log10(params.minPoint.x);
    float logMidPoint = log10(params.midPoint.x);
    float logMaxPoint = log10(params.maxPoint.x);

    float logx = log10(max(x, 1e-6));
    float logy;

    if(logx <= logMinPoint) {
        logy = logx * params.slopeLow + (log10(params.minPoint.y) - params.slopeLow * logMinPoint);
    } else if((logx > logMinPoint) && (logx < logMidPoint)) {
        float knot_coord = (N_KNOTS_LOW - 1) * (logx - logMinPoint) / (logMidPoint - logMinPoint);
        int j = int(knot_coord);
        float t = knot_coord - j;

        vec3 cf = vec3(params.coeffsLow[j], params.coeffsLow[j + 1], params.coeffsLow[j + 2]);

        vec3 monomials = vec3(t * t, t, 1.0);
        logy = dot(monomials, M * cf);
    } else if((logx >= logMidPoint) && (logx < logMaxPoint)) {
        float knot_coord = (N_KNOTS_HIGH - 1) * (logx - logMidPoint) / (logMaxPoint - logMidPoint);
        int j = int(knot_coord);
        float t = knot_coord - j;

        vec3 cf = vec3(params.coeffsHigh[j], params.coeffsHigh[j + 1], params.coeffsHigh[j + 2]);

        vec3 monomials = vec3(t * t, t, 1.0);
        logy = dot(monomials, M * cf);
    } else {
        logy = logx * params.slopeHigh + (log10(params.maxPoint.y) - params.slopeHigh * logMaxPoint);
    }

    return pow(10.0, logy);
}

const SegmentedSplineParams_c9 ODT_48nits = SegmentedSplineParams_c9(
    float[10] ( -1.6989700043, -1.6989700043, -1.4779000000, -1.2291000000, -0.8648000000, -0.4480000000, 0.0051800000, 0.4511080334, 0.9113744414, 0.9113744414 ),
    float[10] ( 0.5154386965, 0.8470437783, 1.1358000000, 1.3802000000, 1.5197000000, 1.5985000000, 1.6467000000, 1.6746091357, 1.6878733390, 1.6878733390 ),
    vec2(0.18 * exp2(-6.5), 0.02),  // minPoint
    vec2(0.18, 4.8),                // midPoint
    vec2(0.18 * exp2( 6.5), 48.0),  // maxPoint
    0.0,  // slopeLow
    0.04  // slopeHigh
);

float segmented_spline_c9_fwd(float x, SegmentedSplineParams_c9 params) { // params should default to ODT_48nits
    const int N_KNOTS_LOW  = 8;
    const int N_KNOTS_HIGH = 8;

    float logMinPoint = log10(params.minPoint.x);
    float logMidPoint = log10(params.midPoint.x);
    float logMaxPoint = log10(params.maxPoint.x);

    float logx = log10(max(x, 1e-6));
    float logy;

    if ( logx <= logMinPoint ) {
        logy = logx * params.slopeLow + (log10(params.minPoint.y) - params.slopeLow * logMinPoint);
    } else if (( logx > logMinPoint ) && ( logx < logMidPoint )) {
        float knot_coord = (N_KNOTS_LOW - 1) * (logx - logMinPoint) / (logMidPoint - logMinPoint);
        int j = int(knot_coord);
        float t = knot_coord - j;

        vec3 cf = vec3(params.coeffsLow[j], params.coeffsLow[j + 1], params.coeffsLow[j + 2]);
        
        vec3 monomials = vec3(t * t, t, 1.0);
        logy = dot(monomials, M * cf);
    } else if (( logx >= logMidPoint ) && ( logx < logMaxPoint )) {
        float knot_coord = (N_KNOTS_HIGH - 1) * (logx - logMidPoint) / (logMaxPoint - logMidPoint);
        int j = int(knot_coord);
        float t = knot_coord - j;

        vec3 cf = vec3(params.coeffsHigh[j], params.coeffsHigh[j + 1], params.coeffsHigh[j + 2]);
        
        vec3 monomials = vec3(t * t, t, 1.0);
        logy = dot(monomials, M * cf);
    } else { //if ( logIn >= logMaxPoint ) {
        logy = logx * params.slopeHigh + (log10(params.maxPoint.y) - params.slopeHigh * logMaxPoint);
    }

    return pow(10.0, logy);
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 RRTAndODTFit(in vec3 rgb) {
	vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
	vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;

	return a / b;
}

vec3 AcademyFit(in vec3 rgb) {
	rgb *= 1.4;

	// Apply RRT sweeteners
	rgb = RRTSweeteners(rgb * AP1toAP0);

	// Apply RRT and ODT
	rgb = RRTAndODTFit(rgb);

	// Global desaturation
	rgb = mix(vec3(luminance(rgb)), rgb, odtSatFactor);

	return linearToSRGB(rgb);
}

//======// ACES Full //===========================================================================//

vec3 RRT(in vec3 aces) {
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

	aces.r += hueWeight * saturation * (rrtRedPivot - aces.r) * oneMinus(rrtRedScale);

    // --- ACES to RGB rendering space --- //
    aces = satU16f(aces);
	vec3 rgbPre = satU16f(aces * AP0toAP1);

	// --- Global desaturation --- //
	float luminance = luminance(rgbPre);
	rgbPre = mix(vec3(luminance), rgbPre, rrtSatFactor);

    // --- Apply the tonescale independently in rendering-space RGB --- //
    vec3 rgbPost;
    rgbPost.r = segmented_spline_c5_fwd(rgbPre.r, RRT_PARAMS);
    rgbPost.g = segmented_spline_c5_fwd(rgbPre.g, RRT_PARAMS);
    rgbPost.b = segmented_spline_c5_fwd(rgbPre.b, RRT_PARAMS);

	return rgbPost;
}

vec3 XYZ_to_xyY(in vec3 XYZ) {
	float mul = 1.0 / max(XYZ.x + XYZ.y + XYZ.z, 1e-10);

	return vec3(
		XYZ.x * mul,
		XYZ.y * mul,
		XYZ.y
	);
}
vec3 xyY_to_XYZ(in vec3 xyY) {
	float mul = xyY.z / max(xyY.y, 1e-10);

	return vec3(
		xyY.x * mul,
		xyY.z,
		(1.0 - xyY.x - xyY.y) * mul
	);
}

vec3 dark_surround_to_dim_surround(in vec3 linearCV) {
	const float dimSurroundGamma = 0.9811;

	vec3 XYZ = linearCV * AP1toXYZ;
	vec3 xyY = XYZ_to_xyY(XYZ);

	xyY.z = max0(xyY.z);
	xyY.z = pow(xyY.z, dimSurroundGamma);

	return xyY_to_XYZ(xyY) * XYZtoAP1;
}


vec3 Y_to_linCV(vec3 Y, const float Ymax, const float Ymin) {
    return (Y - Ymin) / (Ymax - Ymin);
}

float moncurve_r(float y, const float gamma, const float offs) {
    const float yb = pow(offs * gamma / ((gamma - 1.0) * (1.0 + offs)), gamma);
    const float rs = pow((gamma - 1.0) / offs, gamma - 1.0) * pow((1.0 + offs) / gamma, gamma);
    return y >= yb ? (1.0 + offs) * pow(y, 1.0 / gamma) - offs : y * rs;
}

vec3 ODT_sRGB_100nits_dim(in vec3 rgbPre) {
    SegmentedSplineParams_c9 params = ODT_48nits;

    params.minPoint.x = segmented_spline_c5_fwd(params.minPoint.x, RRT_PARAMS);
    params.midPoint.x = segmented_spline_c5_fwd(params.midPoint.x, RRT_PARAMS);
    params.maxPoint.x = segmented_spline_c5_fwd(params.maxPoint.x, RRT_PARAMS);

	// Apply the tonescale independently in rendering-space RGB
	vec3 rgbPost;
	rgbPost.r = segmented_spline_c9_fwd(rgbPre.r, params);
	rgbPost.g = segmented_spline_c9_fwd(rgbPre.g, params);
	rgbPost.b = segmented_spline_c9_fwd(rgbPre.b, params);

	const float cinemaWhite = 48.0;
	const float cinemaBlack = 0.02;

	// Scale luminance to linear code value
	vec3 linearCV = Y_to_linCV(rgbPost, cinemaWhite, cinemaBlack);

	// Apply gamma adjustment to compensate for dim surround
	linearCV = dark_surround_to_dim_surround(linearCV);

	// Apply desaturation to compensate for luminance difference
	float luminance = luminance(linearCV);
	linearCV = mix(vec3(luminance), linearCV, odtSatFactor);

    // Convert to display primary encoding
    // Rendering space RGB to XYZ
    vec3 XYZ = linearCV * AP1toXYZ;

    // Apply CAT from ACES white point to assumed observer adapted white point
    XYZ *= D60ToD65_CAT;

    // CIE XYZ to display primaries
    linearCV = XYZ * XYZtoSRGB;

    // Handle out-of-gamut values
    // Clip values < 0 or > 1 (i.e. projecting outside the display primaries)
    linearCV = saturate(linearCV);

	const float dispGamma = 2.4; 
	const float offset = 0.055;

    // Encode linear code values with transfer function
    vec3 outputCV;
    // moncurve_r with gamma of 2.4 and offset of 0.055 matches the EOTF found in IEC 61966-2-1:1999 (sRGB)
    outputCV.r = moncurve_r(linearCV.r, dispGamma, offset);
    outputCV.g = moncurve_r(linearCV.g, dispGamma, offset);
    outputCV.b = moncurve_r(linearCV.b, dispGamma, offset);

	return outputCV;
}

vec3 bt1886_r(vec3 L, const float gamma, const float Lw, const float Lb) {
    float rGamma = 1.0 / gamma;
    float a = pow(pow(Lw, rGamma) - pow(Lb, rGamma), gamma);
    float b = pow(Lb, rGamma) / (pow(Lw, rGamma) - pow(Lb, rGamma));
    return pow(max(L / a, 0.0), vec3(rGamma)) - b;
}

vec3 ODT_Rec2020_P3D65limited_100nits_dim(in vec3 rgbPre) {
    SegmentedSplineParams_c9 params = ODT_48nits;

    params.minPoint.x = segmented_spline_c5_fwd(params.minPoint.x, RRT_PARAMS);
    params.midPoint.x = segmented_spline_c5_fwd(params.midPoint.x, RRT_PARAMS);
    params.maxPoint.x = segmented_spline_c5_fwd(params.maxPoint.x, RRT_PARAMS);

	// Apply the tonescale independently in rendering-space RGB
	vec3 rgbPost;
	rgbPost.r = segmented_spline_c9_fwd(rgbPre.r, params);
	rgbPost.g = segmented_spline_c9_fwd(rgbPre.g, params);
	rgbPost.b = segmented_spline_c9_fwd(rgbPre.b, params);

	const float cinemaWhite = 48.0;
	const float cinemaBlack = 0.02;

	// Scale luminance to linear code value
	vec3 linearCV = Y_to_linCV(rgbPost, cinemaWhite, cinemaBlack);

	// Apply gamma adjustment to compensate for dim surround
	linearCV = dark_surround_to_dim_surround(linearCV);

	// Apply desaturation to compensate for luminance difference
	float luminance = luminance(linearCV);
	linearCV = mix(vec3(luminance), linearCV, odtSatFactor);

    // Convert to display primary encoding
    // Rendering space RGB to XYZ
    vec3 XYZ = linearCV * AP1toXYZ;

    // Apply CAT from ACES white point to assumed observer adapted white point
    XYZ *= D60ToD65_CAT;

    // CIE XYZ to display primaries
    linearCV = XYZ * XYZtoSRGB;

    // Handle out-of-gamut values
    // Clip values < 0 or > 1 (i.e. projecting outside the display primaries)
    linearCV = saturate(linearCV);

	const float dispGamma = 2.4; 
	const float lW = 1.0; 
	const float lB = 0.0; 

    // Encode linear code values with transfer function
	return bt1886_r(linearCV, dispGamma, lW, lB);
}

const mat3 sRGBtoACES = mat3(
    0.43963298, 0.38298870, 0.17737832,
    0.08977644, 0.81343943, 0.09678413,
    0.01754117, 0.11154655, 0.87091228
);

vec3 AcademyFull(in vec3 rgb) {
	rgb *= 1.4;
	rgb *= sRGBtoACES;

	// Apply RRT
	rgb = RRT(rgb);

	// Apply ODT
	rgb = ODT_sRGB_100nits_dim(rgb);

	return rgb;
}
