// https://github.com/tobspr/GLSL-Color-Spaces/blob/master/ColorSpaces.inc.glsl
vec3 linearToSRGB(in vec3 color) {
	return mix(color * 12.92, 1.055 * pow(color, vec3(0.41666666)) - 0.055, lessThan(vec3(0.0031308), color));
}

vec3 sRGBtoLinear(in vec3 color) {
	return mix(color * 0.07739938, pow((color + 0.055) * 0.94786729, vec3(2.4)), lessThan(vec3(0.04045), color));
}

// https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec3 linearToSRGBApprox(in vec3 color) {
    // vec3 S1 = color * inversesqrt(color);
    // vec3 S2 = S1 * inversesqrt(S1);
    // vec3 S3 = S2 * inversesqrt(S2);
    // return 0.585122381 * S1 + 0.783140355 * S2 - 0.368262736 * S3;
    return pow(color, vec3(1.0 / 2.223));
}

vec3 sRGBtoLinearApprox(in vec3 color) {
    return color * (color * (color * 0.305306011 + 0.682171111) + 0.012522878);
}

float luminance(in vec3 color) {
    // https://en.wikipedia.org/wiki/Luma_(video)
    // const vec3 coeff = vec3(0.2722287168, 0.6740817658, 0.0536895174);
    const vec3 coeff = vec3(0.2126, 0.7152, 0.0722);
    return dot(color, coeff);
}

vec3 colorSaturation(in vec3 color, in float saturation) {
    return mix(vec3(luminance(color)), color, saturation);
}

// Modified from https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/blackbody.glsl
vec3 plancks(in float t, in vec3 lambda) {
    const float h = 6.62607015e-16; // Planck's constant
    const float c = 2.99792458e17;  // The speed of light in a vacuum
    const float k = 1.38064852e-5;  // Boltzmann's constant

    vec3 p1 = (2.0 * h * sqr(c)) / pow5(lambda);
    vec3 p2 = fastExp(h * c / (lambda * k * t)) - vec3(1.0);
    return p1 / p2;
}

vec3 blackbody(in float t) {
    vec3 color = plancks(t, vec3(660.0, 550.0, 440.0));
    return color * rcp(maxOf(color)); // Normalize to 1.0
}

float karisAverage(in vec3 color) {
    return rcp(1.0 + 1e-3 * luminance(color));
}

vec3 reinhard(in vec3 hdr) {
    return hdr * rcp(1.0 + luminance(hdr));
}
vec3 invReinhard(in vec3 sdr) {
    return sdr * rcp(1.0 - luminance(sdr));
}

// https://en.wikipedia.org/wiki/YCoCg
vec3 sRGBToYCoCg(in vec3 rgb) {
    return mat3(
        0.25,  0.50, -0.25,
        0.50,  0.00,  0.50,
        0.25, -0.50, -0.25
    ) * rgb;
}
vec3 YCoCgToSRGB(in vec3 YCoCg) {
    return mat3(
         1.0,  1.0,  1.0,
         1.0,  0.0, -1.0,
        -1.0,  1.0, -1.0
    ) * YCoCg;
}

// Adapted from https://github.com/zubetto/BlackBodyRadiation
// MIT License
// Copyright (c) 2021 Alexander
/*
    This function approximates luminance and chromaticity of a black body radiation emitted at the given temperature.
    Approximation errors are not provided, so this function should not be used where computational accuracy is critical!
    Instead, the primary purpose of this function is to render a black body surface in real time, which can be used in CG shaders,
    therefore the function is written in HLSL.
    
    The luminance and chromaticity of a black body radiation are computed independently of each other.
    The alpha-component of returned value is effective radiance in W/(sr*m2), which 
    should be multiplied by 683.002 lm/W to get the corresponding luminance in cd/m2.
    The rgb-components of returned value are color components expressed in linear sRGB color space.
    Relative luminance of returned color is close to 1 for temperatures above about 1000 K.
    Note, that returned color can have negative components, which means that chromaticity of a black body
    is outside the sRGB gamut for a given temperature (g-component < 0 for temperatures below about 900 K and
    b-component < 0 for temperatures below about 1900 K).
    To get final color of a black body radiation with luminance in cd/m2 
    the rgb-components should be multiplied by the alpha-component and by 683.002 lm/W.
    
    sRGB is defined according to ITU-R BT.709:
                             x       y
        white point   = 0.3127, 0.3290
        red primary   =   0.64,   0.33
        green primary =   0.30,   0.60
        blue primary  =   0.15,	  0.06
    More details can be found here https://www.desmos.com/calculator/qaxw5zb0zc
    
    T - temperature in degrees Kelvin;
    bComputeRadiance - if true, effective radiance is computed;
    bComputeChromaticity - if true, chromaticity is computed;
    
    returns: vec4 ChromaRadiance = {chroma_r, chroma_g, chroma_b, effRadiance}
*/
vec4 BlackBodyRadiation(in float T) {
    if (T <= 0.0) return vec4(0.0);

    vec4 ChromaRadiance;

    // --- Effective radiance in W/(sr*m2) ---
    ChromaRadiance.a = 230141698.067 / (exp2(37112.1757708 / T) - 1.0);

    // luminance Lv = Km*ChromaRadiance.a in cd/m2, where Km = 683.002 lm/W

    // --- Chromaticity in linear sRGB ---
    // (i.e. color luminance Y = dot({r,g,b}, {0.2126, 0.7152, 0.0722}) = 1)
    // --- R ---
    float u = 0.000536332 * T;
    ChromaRadiance.r = 0.638749 + (u + 1.57533) / (u * u + 0.28664);

    // --- G ---
    u = 0.0019639 * T;
    ChromaRadiance.g = 0.971029 + (u - 10.8015) / (u * u + 6.59002);

    // --- B ---
    float p = 0.00668406 * T + 23.3962;
    u = 0.000941064 * T;
    float q = u * u + 0.00100641 * T + 10.9068;
    ChromaRadiance.b = 2.25398 - p / q;

    return ChromaRadiance;
}