//--// AgX Minimal //---------------------------------------------------------//

// From https://iolite-engine.com/blog_posts/minimal_agx_implementation

// MIT License
//
// Copyright (c) 2024 Missing Deadlines (Benjamin Wrensch)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// All values used to derive this implementation are sourced from Troy’s initial AgX implementation/OCIO config file available here:
//   https://github.com/sobotka/AgX

// 0: Default, 1: Golden, 2: Punchy, 3: Custom
#define AGX_LOOK 3 // [0 1 2 3]

// Mean error^2: 3.6705141e-06
vec3 agxDefaultContrastApprox_6th(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return  + 15.5     * x4 * x2
            - 40.14    * x4 * x
            + 31.96    * x4
            - 6.868    * x2 * x
            + 0.4298   * x2
            + 0.1191   * x
            - 0.00232;
}

// Mean error^2: 1.85907662e-06
vec3 agxDefaultContrastApprox_7th(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return - 17.86     * x4 * x2 * x
           + 78.01     * x4 * x2
           - 126.7     * x4 * x
           + 92.06     * x4
           - 28.72     * x2 * x
           + 4.361     * x2
           - 0.1718    * x
           + 0.002857;
}

vec3 agx(vec3 val) {
    const mat3 agx_mat = mat3(
    0.842479062253094, 0.0423282422610123, 0.0423756549057051,
    0.0784335999999992,  0.878468636469772,  0.0784336,
    0.0792237451477643, 0.0791661274605434, 0.879142973793104);

    // const float min_ev = -12.47393f;
    // const float max_ev = 4.026069f;
    const float min_ev = -8.48;
    const float max_ev = 5.52;

    // Input transform (inset)
    val = agx_mat * val;

    // Log2 space encoding
    val = clamp(log2(val * 5.0), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);

    // Apply sigmoid function approximation
    val = agxDefaultContrastApprox_7th(val);

    return val;
}

vec3 agxEotf(vec3 val) {
    const mat3 agx_mat_inv = mat3(
    1.19687900512017, -0.0528968517574562, -0.0529716355144438,
    -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
    -0.0990297440797205, -0.0989611768448433, 1.15107367264116);

    // Inverse input transform (outset)
    val = agx_mat_inv * val;

    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    // NOTE: We're linearizing the output here. Comment/adjust when
    // *not* using a sRGB render target
    // val = pow(val, vec3(2.2));

    return val;
}

vec3 agxLook(vec3 val) {
    const vec3 lw = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(val, lw);

    #if AGX_LOOK == 0
        // Default
        const vec3 slope = vec3(1.0);
        const vec3 power = vec3(1.0);
        const float sat = 1.0;
    #elif AGX_LOOK == 1
        // Golden
        const vec3 slope = vec3(1.0, 0.9, 0.5);
        const vec3 power = vec3(0.8);
        const float sat = 0.8;
    #elif AGX_LOOK == 2
        // Punchy
        const vec3 power = vec3(1.35);
        const float sat = 1.4;
    #else
        // Custom
        const vec3 slope = vec3(1.1);
        const vec3 power = vec3(1.3);
        const float sat = 1.0;
    #endif

    // ASC CDL
    val = pow(val * slope, power);
    return luma + sat * (val - luma);
}

vec3 AgX_Minimal(in vec3 value) {
    value = agx(value);
    value = agxLook(value); // Optional
    return agxEotf(value);
}

// vec3 AgX_Minimal(in vec3 val) {
//     val *= 2.0;

//     const mat3 agx_mat = mat3(
//         0.842479062253094, 0.0423282422610123, 0.0423756549057051,
//         0.0784335999999992,  0.878468636469772,  0.0784336,
//         0.0792237451477643, 0.0791661274605434, 0.879142973793104);

// 	val *= mat3(0.99999976, -1.26657e-7, -1.29064e-9, 1.67316e-8, 0.99999976, -5.32026e-9, -0.00725587, 6.47740e-9, 1.00725580);

//     //const float min_ev = -12.47393f;
//     //const float max_ev = 4.026069f;
//     const float min_ev = -6.0;
//     const float max_ev = 6.0;

//     // Input transform
//     val = agx_mat * val;

//     // Log2 space encoding
//     val = clamp(log2(val * 5.5), min_ev, max_ev);
//     val = (val - min_ev) / (max_ev - min_ev);

//     // Apply sigmoid function approximation
//     val = agxDefaultContrastApprox_7th(val);

//     //const vec3 lw = vec3(0.2126, 0.7152, 0.0722);
//     //float luma = dot(val, lw);
//     //float luma = GetLuminance(val);

//     const mat3 agx_mat_inv = mat3(
//         1.19687900512017, -0.0528968517574562, -0.0529716355144438,
//         -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
//         -0.0990297440797205, -0.0989611768448433, 1.15107367264116
//     );

//     // Undo input transform
//     return agx_mat_inv * val;
// }


//--// AgX Full //------------------------------------------------------------//

// Matrices for rec 2020 <> rec 709 color space conversion
// matrix provided in row-major order so it has been transposed
// https://www.itu.int/pub/R-REP-BT.2407-2017
const mat3 LINEAR_REC2020_TO_LINEAR_SRGB = mat3(
	vec3(  1.660491, -0.124550, -0.018151 ),
	vec3( -0.587641,  1.132900, -0.100579 ),
	vec3( -0.072850, -0.008349,  1.118730 ));

const mat3 LINEAR_SRGB_TO_LINEAR_REC2020 = mat3(
	vec3( 0.627404, 0.069097, 0.016391 ),
	vec3( 0.329283, 0.919540, 0.088013 ),
	vec3( 0.043313, 0.011362, 0.895595 ));


const float slope = 2.0;
const float toe_power = 3.0;
const float shoulder_power = 3.25;

const vec3 compression = vec3(0.1, 0.1, 0.15);
const vec3 rotation = vec3(2.0, -1.0, -3.0);

vec3 unproject(vec2 xy) {
    if (xy.y == 0.0) return vec3(0.0);

    float Y = 1.0;
    float X = xy.x / xy.y;
    float Z = (1.0 - xy.x - xy.y) / xy.y;

    return vec3(X, Y, Z);
}

mat3 primaries_to_matrix(vec2 xy_red, vec2 xy_green, vec2 xy_blue, vec2 xy_white) {
    vec3 XYZ_red = unproject(xy_red);
    vec3 XYZ_green = unproject(xy_green);
    vec3 XYZ_blue = unproject(xy_blue);

    vec3 XYZ_white = unproject(xy_white);

    mat3 temp = mat3(
                XYZ_red.x,	XYZ_green.x,	XYZ_blue.x,
                1.0,        1.0,            1.0,
                XYZ_red.z,	XYZ_green.z,	XYZ_blue.z);

    mat3 inverse = inverse(temp);
    vec3 scale = XYZ_white * inverse;

    return mat3(
        scale.x * XYZ_red.x, scale.y * XYZ_green.x,	scale.z * XYZ_blue.x,
        scale.x * XYZ_red.y, scale.y * XYZ_green.y,	scale.z * XYZ_blue.y,
        scale.x * XYZ_red.z, scale.y * XYZ_green.z,	scale.z * XYZ_blue.z);
}

float RotationToSlide(vec2 primary, vec2 neighborA, vec2 neighborB, float angle) {
	vec2 neighbor = angle >= 0.0 ? neighborA : neighborB;

	float distance_to_neighbor = distance(primary, neighbor);
	float distance_to_center = length(primary);

	float side = sin(angle / 180.0 * PI) * distance_to_center;

	return side / distance_to_neighbor;
}

vec2 SlidePrimary(vec2 primary, vec2 neighborA, vec2 neighborB, float amount) {
	return mix(primary, amount >= 0.0 ? neighborA : neighborB, saturate(abs(amount)));
}

mat3 ComputeCompressionMatrix(vec2 xyR, vec2 xyG, vec2 xyB, vec2 xyW) {
	vec2 offsetR = xyR - xyW;
	vec2 offsetG = xyG - xyW;
	vec2 offsetB = xyB - xyW;

	vec3 slide = vec3(0.0);
	slide.r = RotationToSlide(offsetR, offsetB, offsetG, rotation.r);
	slide.g = RotationToSlide(offsetG, offsetR, offsetB, rotation.g);
	slide.b = RotationToSlide(offsetB, offsetG, offsetR, rotation.b);

	vec3 scale_factor = 1.0 / (1.0 - compression);

	vec2 R = (SlidePrimary(offsetR, offsetB, offsetG, slide.r) * scale_factor.r) + xyW;
	vec2 G = (SlidePrimary(offsetG, offsetR, offsetB, slide.g) * scale_factor.g) + xyW;
	vec2 B = (SlidePrimary(offsetB, offsetG, offsetR, slide.b) * scale_factor.b) + xyW;
	vec2 W = xyW;

	return primaries_to_matrix(R, G, B, W);
}

vec3 open_domain_to_normalized_log2(vec3 in_od, float minimum_ev, float maximum_ev) {
    const float middle_grey = 0.18;
    float total_exposure = maximum_ev - minimum_ev;

    vec3 output_log = clamp(log2(in_od / middle_grey), minimum_ev, maximum_ev);

    return (output_log - minimum_ev) / total_exposure;
}

float equation_scale(float x_pivot, float y_pivot, float slope_pivot, float power) {
    return pow(pow((slope_pivot * x_pivot), -power) * (pow((slope_pivot * (x_pivot / y_pivot)), power) - 1.0), -1.0 / power);
}

float equation_hyperbolic(float x, float power) {
    return x * pow(1.0 + pow(x, power), -1.0 / power);
}

float equation_term(float x, float x_pivot, float slope_pivot, float scale) {
    return (slope_pivot * (x - x_pivot)) / scale;
}

float equation_curve(float x, float x_pivot, float y_pivot, float slope_pivot, float toe_power, float shoulder_power, float scale) {
    if (scale < 0.0) {
        return scale * equation_hyperbolic(equation_term(x, x_pivot, slope_pivot, scale), toe_power) + y_pivot;
    } else {
        return scale * equation_hyperbolic(equation_term(x,x_pivot,slope_pivot,scale), shoulder_power) + y_pivot;
    }
}

float equation_full_curve(float x, float x_pivot, float y_pivot, float slope_pivot, float toe_power, float shoulder_power) {
    bool bpivot = x >= x_pivot;
    float scale_x_pivot = mix(x_pivot, 1.0 - x_pivot, bpivot);
    float scale_y_pivot = mix(y_pivot, 1.0 - y_pivot, bpivot);

    float toe_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, toe_power);
    float shoulder_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, shoulder_power);

    float scale = mix(-toe_scale, shoulder_scale, bpivot);

    return equation_curve(x, x_pivot, y_pivot, slope_pivot, toe_power, shoulder_power, scale);
}

vec3 AgXConfigurable(in vec3 rgb) {
    mat3 sRGB_to_XYZ = primaries_to_matrix(
        vec2(0.708,0.292),
		vec2(0.170,0.797),
		vec2(0.131,0.046),
		vec2(0.3127, 0.3290));

    mat3 adjusted_to_XYZ = ComputeCompressionMatrix(
        vec2(0.708,0.292),
		vec2(0.170,0.797),
		vec2(0.131,0.046),
		vec2(0.3127, 0.3290));

    mat3 XYZ_to_adjusted = inverse(adjusted_to_XYZ);

    vec3 xyz = rgb * sRGB_to_XYZ;
    vec3 ajustedRGB = xyz * XYZ_to_adjusted;

    const float min_ev = -8.48;
    const float max_ev = 5.52;

    float x_pivot = abs(min_ev) / (max_ev - min_ev);
    float y_pivot = 0.5;

    vec3 logRGB = open_domain_to_normalized_log2(ajustedRGB, min_ev, max_ev);

    float outputR = equation_full_curve(logRGB.r, x_pivot, y_pivot, slope, toe_power, shoulder_power);
    float outputG = equation_full_curve(logRGB.g, x_pivot, y_pivot, slope, toe_power, shoulder_power);
    float outputB = equation_full_curve(logRGB.b, x_pivot, y_pivot, slope, toe_power, shoulder_power);

    return saturate(vec3(outputR, outputG, outputB));
}

vec3 AgX_Full(in vec3 rgb) {
    rgb = LINEAR_SRGB_TO_LINEAR_REC2020 * rgb;
    rgb = AgXConfigurable(rgb);

    rgb = sRGBtoLinear(rgb);
    rgb = LINEAR_REC2020_TO_LINEAR_SRGB * rgb;

    return linearToSRGB(rgb);
}
