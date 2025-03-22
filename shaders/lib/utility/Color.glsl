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

vec3 karisAverage(in vec3 color) {
    const float k = 1e-3; // Empirical constant
    return color * rcp(1.0 + k * luminance(color));
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
