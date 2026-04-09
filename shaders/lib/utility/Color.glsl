
const mat3 Rec2020_2_sRGB = mat3(
     1.6603034854, -0.5875701425, -0.0728900602,
    -0.1243755953,  1.1328344814, -0.0083597372,
    -0.0181122800, -0.1005836085,  1.1187703262
);

const mat3 sRGB_2_Rec2020 = mat3(
    0.6274413721, 0.3292974595, 0.0433514584,
    0.0690276171, 0.9195806669, 0.0113614226,
    0.0163642351, 0.0880171625, 0.8955649727
);

const mat3 sRGB_2_XYZ = mat3(
	0.4124564, 0.3575761, 0.1804375,
	0.2126729, 0.7151522, 0.0721750,
	0.0193339, 0.1191920, 0.9503041
);

const mat3 XYZ_2_sRGB = mat3(
	 3.2409699419, -1.5373831776, -0.4986107603,
	-0.9692436363,  1.8759675015,  0.0415550574,
	 0.0556300797, -0.2039769589,  1.0569715142
);

const mat3 XYZ_2_Rec2020 = mat3(
     1.716651188,  -0.3556707838, -0.2533662814,
    -0.6666843518,  1.6164812366,  0.0157685458,
     0.0176398574, -0.0427706133,  0.9421031212
);

const mat3 Rec2020_2_XYZ = mat3(
    0.6369580483, 0.1446169036, 0.1688809752,
    0.2627002120, 0.6779980715, 0.0593017165,
    0.0000000000, 0.0280726930, 1.0609850577
);

// https://en.wikipedia.org/wiki/SRGB
// https://github.com/tobspr/GLSL-Color-Spaces/blob/master/ColorSpaces.inc.glsl
vec3 linearToSRGB(vec3 color) {
	return mix(color * 12.92, 1.055 * pow(color, vec3(0.41666666)) - 0.055, step(vec3(0.0031308), color));
}

vec3 sRGBToLinear(vec3 color) {
	return mix(color * 0.07739938, pow((color + 0.055) * 0.94786729, vec3(2.4)), step(vec3(0.04045), color));
}

// https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec3 linearToSRGBApprox(vec3 color) {
    vec3 S1 = color * inversesqrt(color);
    vec3 S2 = S1 * inversesqrt(S1);
    vec3 S3 = S2 * inversesqrt(S2);
    return 0.585122381 * S1 + 0.783140355 * S2 - 0.368262736 * S3;
}

vec3 sRGBToLinearApprox(vec3 color) {
    return color * (color * (color * 0.305306011 + 0.682171111) + 0.012522878);
}

// https://en.wikipedia.org/wiki/YCoCg
vec3 RGBToYCoCg(vec3 rgb) {
    return mat3(
        0.25,  0.50, -0.25,
        0.50,  0.00,  0.50,
        0.25, -0.50, -0.25
    ) * rgb;
}
vec3 YCoCgToRGB(vec3 YCoCg) {
    return mat3(
         1.0,  1.0,  1.0,
         1.0,  0.0, -1.0,
        -1.0,  1.0, -1.0
    ) * YCoCg;
}

float luminance(vec3 color) {
    return dot(color, vec3(0.2126729, 0.7151522, 0.0721750));
}

vec3 desaturate(vec3 color, float amount) {
    return mix(color, vec3(luminance(color)), amount);
}

float karisAverage(vec3 color) {
    return rcp(1.0 + luminance(color));
}

vec3 reinhard(vec3 hdr) {
    return hdr * rcp(1.0 + luminance(hdr));
}
vec3 invReinhard(vec3 sdr) {
    return sdr * rcp(1.0 - luminance(sdr));
}

// Inspired by GPU Zen 4
vec3 TonemapRadiance(vec3 v, float e) {
    return v * pow(luminance(v) + EPS, e - 1.0);
}
vec3 InverseTonemapRadiance(vec3 v, float e) {
    return v * pow(luminance(v) + EPS, rcp(e) - 1.0);
}

//================================================================================================//

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
    should be multiplied by 128.002 lm/W to get the corresponding luminance in cd/m2.
    The rgb-components of returned value are color components expressed in linear sRGB color space.
    Relative luminance of returned color is close to 1 for temperatures above about 1000 K.
    Note, that returned color can have negative components, which means that chromaticity of a black body
    is outside the sRGB gamut for a given temperature (g-component < 0 for temperatures below about 900 K and
    b-component < 0 for temperatures below about 1900 K).
    To get final color of a black body radiation with luminance in cd/m2
    the rgb-components should be multiplied by the alpha-component and by 128.002 lm/W.

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
vec4 BlackBodyRadiation(float T) {
    if (T <= 0.0) return vec4(0.0);

    vec4 ChromaRadiance;

    // --- Effective radiance in W/(sr*m2) ---
    ChromaRadiance.a = 230141698.067 / (exp2(37112.1757708 / T) - 1.0);

    // luminance Lv = Km*ChromaRadiance.a in cd/m2, where Km = 128.002 lm/W

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