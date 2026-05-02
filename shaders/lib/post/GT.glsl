//======// GT //==================================================================================//

// Uchimura 2017, "HDR theory and practice"
// Math: https://www.desmos.com/calculator/gslcdxvipg
// Source: https://www.slideshare.net/nikuque/hdr-theory-and-practicce-jp
vec3 GT(in vec3 x) {
	#ifdef HDR_ENABLED
		float maxDisplayBrightness = HdrGamePeakBrightness / HdrGamePaperWhiteBrightness;
	#else
		const float maxDisplayBrightness = 1.0;
	#endif
	const float contrast			 = 1.0;
	const float linearStart			 = 0.2;
	const float linearLength		 = 0.1;
	const float black				 = 1.33;
	const float pedestal			 = 0.0;

	const float l0 = ((maxDisplayBrightness - linearStart) * linearLength) / contrast;
	const float L0 = linearStart - linearStart / contrast;
	const float L1 = linearStart + oms(linearStart) / contrast;
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

	return T * w0 + L * w1 + S * w2;
}

//======// GT7 //=================================================================================//

// Source: https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp

// MIT License
//
// Copyright (c) 2025 Polyphony Digital Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// -----------------------------------------------------------------------------
// Mode options.
// -----------------------------------------------------------------------------
#define TONE_MAPPING_UCS_ICTCP  0
#define TONE_MAPPING_UCS_JZAZBZ 1
#define TONE_MAPPING_UCS        TONE_MAPPING_UCS_ICTCP

// -----------------------------------------------------------------------------
// Defines the SDR reference white level used in our tone mapping (typically 250 nits).
// -----------------------------------------------------------------------------
#ifdef HDR_ENABLED
#define GRAN_TURISMO_SDR_PAPER_WHITE HdrGamePaperWhiteBrightness // cd/m^2
#else
#define GRAN_TURISMO_SDR_PAPER_WHITE 250.0f // cd/m^2
#endif

// -----------------------------------------------------------------------------
// Gran Turismo luminance-scale conversion helpers.
// In Gran Turismo, 1.0f in the linear frame-buffer space corresponds to
// REFERENCE_LUMINANCE cd/m^2 of physical luminance (typically 100 cd/m^2).
// -----------------------------------------------------------------------------
#define REFERENCE_LUMINANCE 100.0f // cd/m^2 <-> 1.0f

float
frameBufferValueToPhysicalValue(float fbValue)
{
	// Converts linear frame-buffer value to physical luminance (cd/m^2)
	// where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
	return fbValue * REFERENCE_LUMINANCE;
}

float
physicalValueToFrameBufferValue(float physical)
{
	// Converts physical luminance (cd/m^2) to a linear frame-buffer value,
	// where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
	return physical / REFERENCE_LUMINANCE;
}

// -----------------------------------------------------------------------------
// Utility functions.
// -----------------------------------------------------------------------------
float
chromaCurve(float x, float a, float b)
{
	return 1.0f - smoothstep(a, b, x);
}

// -----------------------------------------------------------------------------
// "GT Tone Mapping" curve with convergent shoulder.
// -----------------------------------------------------------------------------
struct GTToneMappingCurveV2
{
	float peakIntensity_;
	float alpha_;
	float midPoint_;
	float linearSection_;
	float toeStrength_;
	float kA_, kB_, kC_;
};

void initializeCurve(float monitorIntensity,
						float alpha,
						float grayPoint,
						float linearSection,
						float toeStrength,
						inout GTToneMappingCurveV2 curve)
{
	curve.peakIntensity_ = monitorIntensity;
	curve.alpha_         = alpha;
	curve.midPoint_      = grayPoint;
	curve.linearSection_ = linearSection;
	curve.toeStrength_   = toeStrength;

	// Pre-compute constants for the shoulder region.
	float k = (curve.linearSection_ - 1.0f) / (curve.alpha_ - 1.0f);
	curve.kA_     = curve.peakIntensity_ * curve.linearSection_ + curve.peakIntensity_ * k;
	curve.kB_     = -curve.peakIntensity_ * k * exp(curve.linearSection_ / k);
	curve.kC_     = -1.0f / (k * curve.peakIntensity_);
}

float evaluateCurve(float x, GTToneMappingCurveV2 curve)
{
	if (x < 0.0f)
	{
		return 0.0f;
	}

	float weightLinear = smoothstep(0.0f, curve.midPoint_, x);
	float weightToe    = 1.0f - weightLinear;

	// Shoulder mapping for highlights.
	float shoulder = curve.kA_ + curve.kB_ * exp(x * curve.kC_);

	if (x < curve.linearSection_ * curve.peakIntensity_)
	{
		float toeMapped = curve.midPoint_ * pow(x / curve.midPoint_, curve.toeStrength_);
		return weightToe * toeMapped + weightLinear * x;
	}
	else
	{
		return shoulder;
	}
}

// -----------------------------------------------------------------------------
// EOTF / inverse-EOTF for ST-2084 (PQ).
// Note: Introduce exponentScaleFactor to allow scaling of the exponent in the EOTF for Jzazbz.
// -----------------------------------------------------------------------------
float
eotfSt2084(float n, float exponentScaleFactor)
{
	n = saturate(n);

	// Base functions from SMPTE ST 2084:2014
	// Converts from normalized PQ (0-1) to absolute luminance in cd/m^2 (linear light)
	// Assumes float input; does not handle integer encoding (Annex)
	// Assumes full-range signal (0-1)
	const float m1  = 0.1593017578125f;                // (2610 / 4096) / 4
		float m2  = 78.84375f * exponentScaleFactor; // (2523 / 4096) * 128
	const float c1  = 0.8359375f;                      // 3424 / 4096
	const float c2  = 18.8515625f;                     // (2413 / 4096) * 32
	const float c3  = 18.6875f;                        // (2392 / 4096) * 32
	const float pqC = 10000.0f;                        // Maximum luminance supported by PQ (cd/m^2)

	// Does not handle signal range from 2084 - assumes full range (0-1)
	float np = pow(n, 1.0f / m2);
	float l  = max0(np - c1);

	l = l / (c2 - c3 * np);
	l = pow(l, 1.0f / m1);

	// Convert absolute luminance (cd/m^2) into the frame-buffer linear scale.
	return physicalValueToFrameBufferValue(l * pqC);
}

float
inverseEotfSt2084(float v, float exponentScaleFactor)
{
	const float m1  = 0.1593017578125f;
	float m2  = 78.84375f * exponentScaleFactor;
	const float c1  = 0.8359375f;
	const float c2  = 18.8515625f;
	const float c3  = 18.6875f;
	const float pqC = 10000.0f;

	// Convert the frame-buffer linear scale into absolute luminance (cd/m^2).
	float physical = frameBufferValueToPhysicalValue(v);
	float y        = physical * rcp(pqC); // Normalize for the ST-2084 curve

	float ym = pow(y, m1);
	return exp2(m2 * (log2(c1 + c2 * ym) - log2(1.0f + c3 * ym)));
}

// -----------------------------------------------------------------------------
// ICtCp conversion.
// Reference: ITU-T T.302 (https://www.itu.int/rec/T-REC-T.302/en)
// -----------------------------------------------------------------------------
void
rgbToICtCp(vec3 rgb, out vec3 ictCp) // Input: linear Rec.2020
{
	float l = dot(rgb, vec3(0.4121093750000000, 0.5239257812500000, 0.0639648437500000));
	float m = dot(rgb, vec3(0.1667480468750000, 0.7204589843750000, 0.1127929687500000));
	float s = dot(rgb, vec3(0.0241699218750000, 0.0754394531250000, 0.9003906250000000));

	float lPQ = inverseEotfSt2084(l, 1.0);
	float mPQ = inverseEotfSt2084(m, 1.0);
	float sPQ = inverseEotfSt2084(s, 1.0);

	ictCp[0] = 0.5 * lPQ + 0.5 * mPQ;
	ictCp[1] = 1.613769531250000 * lPQ - 3.323486328125000 * mPQ + 1.709716796875000 * sPQ;
	ictCp[2] = 4.378173828125000 * lPQ - 4.245605468750000 * mPQ - 0.132568359375000 * sPQ;
}

void
iCtCpToRgb(vec3 ictCp, out vec3 rgb) // Output: linear Rec.2020
{
	float l = dot(ictCp, vec3(1.0,  0.00860903703793281,  0.11102962500302593));
	float m = dot(ictCp, vec3(1.0, -0.00860903703793281, -0.11102962500302593));
	float s = dot(ictCp, vec3(1.0,  0.56003133571067909, -0.32062717498731880));

	float lLin = eotfSt2084(l, 1.0);
	float mLin = eotfSt2084(m, 1.0);
	float sLin = eotfSt2084(s, 1.0);

	rgb[0] =  3.4366066943330793 * lLin - 2.5064521186562705 * mLin + 0.0698454243231915 * sLin;
	rgb[1] = -0.7913295555989289 * lLin + 1.9836004517922909 * mLin - 0.1922708961933620 * sLin;
	rgb[2] = -0.0259498996905927 * lLin - 0.0989137147117265 * mLin + 1.1248636144023192 * sLin;
}

// -----------------------------------------------------------------------------
// Jzazbz conversion.
// Reference:
// Muhammad Safdar, Guihua Cui, Youn Jin Kim, and Ming Ronnier Luo,
// "Perceptually uniform color space for image signals including high dynamic
// range and wide gamut," Opt. Express 25, 15131-15151 (2017)
// Note: Coefficients adjusted for linear Rec.2020
// -----------------------------------------------------------------------------
#define JZAZBZ_EXPONENT_SCALE_FACTOR 1.7f // Scale factor for exponent

void
rgbToJzazbz(vec3 rgb, inout vec3 jab) // Input: linear Rec.2020
{
	float l = dot(rgb, vec3(0.530004, 0.355704, 0.086090));
	float m = dot(rgb, vec3(0.289388, 0.525395, 0.157481));
	float s = dot(rgb, vec3(0.091098, 0.147588, 0.734234));

	float lPQ = inverseEotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
	float mPQ = inverseEotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
	float sPQ = inverseEotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

	float iz = 0.5f * lPQ + 0.5f * mPQ;

	jab[0] = (0.44f * iz) / (1.0f - 0.56f * iz) - 1.6295499532821566e-11f;
	jab[1] = 3.524000f * lPQ - 4.066708f * mPQ + 0.542708f * sPQ;
	jab[2] = 0.199076f * lPQ + 1.096799f * mPQ - 1.295875f * sPQ;
}

void
jzazbzToRgb(vec3 jab, inout vec3 rgb) // Output: linear Rec.2020
{
	float jz = jab[0] + 1.6295499532821566e-11f;
	float iz = jz / (0.44f + 0.56f * jz);
	float a  = jab[1];
	float b  = jab[2];

	float l = iz + a * 1.386050432715393e-1f + b * 5.804731615611869e-2f;
	float m = iz + a * -1.386050432715393e-1f + b * -5.804731615611869e-2f;
	float s = iz + a * -9.601924202631895e-2f + b * -8.118918960560390e-1f;

	float lLin = eotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
	float mLin = eotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
	float sLin = eotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

	rgb[0] = lLin * 2.990669f + mLin * -2.049742f + sLin * 0.088977f;
	rgb[1] = lLin * -1.634525f + mLin * 3.145627f + sLin * -0.483037f;
	rgb[2] = lLin * -0.042505f + mLin * -0.377983f + sLin * 1.448019f;
}

// -----------------------------------------------------------------------------
// Unified color space (UCS): ICtCp or Jzazbz.
// -----------------------------------------------------------------------------
#if TONE_MAPPING_UCS == TONE_MAPPING_UCS_ICTCP
#define rgbToUcs rgbToICtCp
#define ucsToRgb iCtCpToRgb
#elif TONE_MAPPING_UCS == TONE_MAPPING_UCS_JZAZBZ
#define rgbToUcs rgbToJzazbz
#define ucsToRgb jzazbzToRgb
#else
#error "Unsupported TONE_MAPPING_UCS value. Please define TONE_MAPPING_UCS as either TONE_MAPPING_UCS_ICTCP or TONE_MAPPING_UCS_JZAZBZ."
#endif

// -----------------------------------------------------------------------------
// GT7 Tone Mapping class.
// -----------------------------------------------------------------------------
struct GT7ToneMapping
{
	float sdrCorrectionFactor_;

	float framebufferLuminanceTarget_;
	float framebufferLuminanceTargetUcs_; // Target luminance in UCS space
	GTToneMappingCurveV2 curve_;

	float blendRatio_;
	float fadeStart_;
	float fadeEnd_;
};

// Initializes the tone mapping curve and related parameters based on the target display luminance.
// This method should not be called directly. Use initializeAsHDR() or initializeAsSDR() instead.
void initializeParameters(float physicalTargetLuminance, inout GT7ToneMapping tm)
{
	tm.framebufferLuminanceTarget_ = physicalValueToFrameBufferValue(physicalTargetLuminance);

	// Initialize the curve (slightly different parameters from GT Sport).
	initializeCurve(tm.framebufferLuminanceTarget_, 0.25f, 0.538f, 0.444f, 1.280f, tm.curve_);

	// Default parameters.
	tm.blendRatio_ = 0.6f;
	tm.fadeStart_  = 0.98f;
	tm.fadeEnd_    = 1.16f;

	vec3 ucs;
	vec3 rgb = vec3( tm.framebufferLuminanceTarget_,
					tm.framebufferLuminanceTarget_,
					tm.framebufferLuminanceTarget_ );
	rgbToUcs(rgb, ucs);
	tm.framebufferLuminanceTargetUcs_ = ucs[0]; // Use the first UCS component (I or Jz) as luminance
}

// Initialize for HDR (High Dynamic Range) display.
// Input: target display peak luminance in nits (range: 250 to 10,000)
// Note: The lower limit is 250 because the parameters for GTToneMappingCurveV2
//       were determined based on an SDR paper white assumption of 250 nits (GRAN_TURISMO_SDR_PAPER_WHITE).
void initializeAsHDR(float physicalTargetLuminance, inout GT7ToneMapping tm)
{
	tm.sdrCorrectionFactor_ = 1.0f;
	initializeParameters(physicalTargetLuminance, tm);
}

// Initialize for SDR (Standard Dynamic Range) display.
void initializeAsSDR(inout GT7ToneMapping tm)
{
	tm.sdrCorrectionFactor_ = 1.0f / physicalValueToFrameBufferValue(GRAN_TURISMO_SDR_PAPER_WHITE);
	initializeParameters(GRAN_TURISMO_SDR_PAPER_WHITE, tm);
}

// Input:  linear Rec.2020 RGB (frame buffer values)
// Output: tone-mapped RGB (frame buffer values);
//         - in SDR mode: mapped to [0, 1], ready for sRGB OETF
//         - in HDR mode: mapped to [0, framebufferLuminanceTarget_], ready for PQ inverse-EOTF
// Note: framebufferLuminanceTarget_ represents the display's target peak luminance converted to a frame buffer value.
//       The returned values are suitable for applying the appropriate OETF to generate final output signal.
void applyToneMapping(inout vec3 rgb, GT7ToneMapping tm)
{
	// Convert to UCS to separate luminance and chroma.
	vec3 ucs;
	rgbToUcs(rgb, ucs);

	// Per-channel tone mapping ("skewed" color).
	vec3 skewedRgb = vec3( evaluateCurve(rgb[0], tm.curve_),
						evaluateCurve(rgb[1], tm.curve_),
						evaluateCurve(rgb[2], tm.curve_));

	vec3 skewedUcs;
	rgbToUcs(skewedRgb, skewedUcs);

	float chromaScale =
		chromaCurve(ucs[0] / tm.framebufferLuminanceTargetUcs_, tm.fadeStart_, tm.fadeEnd_);

	vec3 scaledUcs = vec3(skewedUcs[0],         // Luminance from skewed color
						ucs[1] * chromaScale, // Scaled chroma components
						ucs[2] * chromaScale);

	// Convert back to RGB.
	vec3 scaledRgb;
	ucsToRgb(scaledUcs, scaledRgb);

	// Final blend between per-channel and UCS-scaled results.
	vec3 blended = (1.0f - tm.blendRatio_) * skewedRgb + tm.blendRatio_ * scaledRgb;
	// When using SDR, apply the correction factor.
	// When using HDR, sdrCorrectionFactor_ is 1.0f, so it has no effect.
	rgb = tm.sdrCorrectionFactor_ * min(blended, tm.framebufferLuminanceTarget_);
}

vec3 GT7(vec3 color) {
	GT7ToneMapping tm;
	#ifdef HDR_ENABLED
		initializeAsHDR(HdrGamePeakBrightness, tm);
	#else
		initializeAsSDR(tm);
	#endif

	applyToneMapping(color, tm);

	return color;
}
