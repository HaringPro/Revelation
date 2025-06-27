#if defined NORMAL_MAPPING
	void DecodeNormalTex(inout vec3 normalTex) {
        if (any(greaterThan(normalTex, vec3(0.003)))) {
			normalTex = normalTex * 2.0 - 1.0 + r255;
			#if TEXTURE_FORMAT == 0
				normalTex.z = sqrt(saturate(oms(sdot(normalTex.xy))));
			#else
				normalTex = normalize(normalTex);
			#endif
    		normalTex.xy = uintBitsToFloat(floatBitsToUint(max0(abs(normalTex.xy) - r255)) ^ (floatBitsToUint(normalTex.xy) & 0x80000000u));
		}
	}
#endif

float Packup2x8(in vec2 data) {
	return dot(floor(data * max8f + 0.5), vec2(256.0 / max16f, 1.0 / max16f));
}

float PackupDithered2x8(in vec2 data, in float dither) {
	return dot(floor(data * max8f + dither), vec2(256.0 / max16f, 1.0 / max16f));
}

vec2 Unpack2x8(in float data) {
	float x, y = modf(data * (max16f / 256.0), x) * 256.0;
	return vec2(x, y) * r255;
}

float Packup2x8X(in float data) { return floor(data * (max16f / 256.0)) * r255; }
float Packup2x8Y(in float data) { return fract(data * (max16f / 256.0)) * (256.0 * r255); }

float Packup2x8F(in vec2 data) {
	return dot(floor(data * max8f + 0.5), vec2(256.0, 1.0));
}

vec2 Unpack2x8F(in float data) {
	float x, y = modf(data * rcp(256.0), x) * 256.0;
	return vec2(x, y) * r255;
}

uint Packup2x8U(in vec2 data) {
	uvec2 u = uvec2(data * max8f + 0.5);
	return (u.x << 8) | u.y;
}

uint PackupDithered2x8U(in vec2 data, in float dither) {
	uvec2 u = uvec2(data * max8f + dither);
	return (u.x << 8) | u.y;
}

vec2 Unpack2x8U(in uint data) {
	return vec2(float(data >> 8), float(data & 0xFF)) * r255;
}

float Unpack2x8UX(in uint data) { return float(data >> 8) * r255; }
float Unpack2x8UY(in uint data) { return float(data & 0xFF) * r255; }

uint PackupR11G11B10(in vec3 data) {
	uvec3 u = uvec3(data * vec3(2047.0, 2047.0, 1023.0) + 0.5);
	return (u.x << 21) | (u.y << 10) | u.z;
}

vec3 UnpackR11G11B10(in uint data) {
	return vec3(float(data >> 21) * rcp(2047.0), float((data >> 10) & 0x7FF) * rcp(2047.0), float(data & 0x3FF) * rcp(1023.0));
}

// Octahedral encoding
// https://jcgt.org/published/0003/02/01/paper.pdf
vec2 OctEncodeSnorm(in vec3 dir) {
    dir.xy *= 1.0 / dot(vec3(1.0), abs(dir));
    vec2 oct = mix((1.0 - abs(dir.yx)) * fastSign(dir.xy), dir.xy, step(0.0, dir.z));
    return oct;
}

vec3 OctDecodeSnorm(in vec2 oct) {
    vec3 dir = vec3(oct.x, oct.y, 1.0 - abs(oct.x) - abs(oct.y));
    float t = saturate(-dir.z);
    dir.xy += mix(vec2(t), vec2(-t), step(0.0, dir.xy));
    return normalize(dir);
}

vec2 OctEncodeUnorm(in vec3 dir) {
    return OctEncodeSnorm(dir) * 0.5 + 0.5;
}

vec3 OctDecodeUnorm(in vec2 oct) {
	return OctDecodeSnorm(oct * 2.0 - 1.0);
}

// Spherical coordinate encoding
vec2 sphericalToCartesian(in vec3 dir) {
	vec2 coord = vec2(atan(-dir.x, -dir.z), fastAcos(dir.y));
    return vec2(coord.x * rTAU + 0.5, coord.y * rPI);
}

vec3 cartesianToSpherical(in vec2 coord) {
    coord *= vec2(TAU, PI);
    return vec3(sincos(coord.x) * sin(coord.y), cos(coord.y)).xzy;
}

// Mercator projection
vec2 ProjectMercator(in vec3 dir) {
    float phi = atan(dir.z, dir.x); // Longitude
    float theta = fastAsin(dir.y); // Latitude

    vec2 uv = vec2(phi, log(tan(PI * 0.25 + theta * 0.5)));
    return uv * rTAU + 0.5; // Scale to [0, 1]
}

vec3 UnprojectMercator(in vec2 uv) {
    uv = uv * TAU - PI; // Scale to [-π, π]
    float phi = uv.x; // Longitude
    float theta = atan(fastExp(uv.y)) * 2.0 - hPI; // Latitude

    vec3 dir = vec3(cos(theta) * cos(phi), sin(theta), cos(theta) * sin(phi));
    return normalize(dir);
}

// RGBE32 encoding
// Exponent range: [-128, 127]
uint EncodeRGBE32U(in vec3 data) {
	float e = floor(log2(maxOf(data)));

	float scale = exp2(-e) * 255.0;
	uvec4 rgbe = uvec4(min(uvec3(round(data * scale)), uvec3(255u)), e + 128.0);
	rgbe <<= uvec4(0u, 8u, 16u, 24u);

    return rgbe.x | rgbe.y | rgbe.z | rgbe.w;
}

vec3 DecodeRGBE32U(in uint data) {
    uvec4 rgbe = data >> uvec4(0u, 8u, 16u, 24u) & 0xFFu;

    float e = floor(rgbe.a) - 128.0;
    float scale = exp2(e) * r255;

    return rgbe.rgb * scale;
}

// Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007.
// https://realtimecollisiondetection.net/blog/?p=15

// M matrix, for encoding
const mat3 logLuvM = mat3(
    0.2209, 0.3390, 0.4184,
    0.1138, 0.6780, 0.7319,
    0.0102, 0.1130, 0.2969
);

// Inverse M matrix, for decoding
const mat3 logLuvInverseM = mat3(
    6.0014, -2.7008, -1.7996,
   -1.3320,  3.1029, -5.7721,
    0.3008, -1.0882,  5.6268
);

vec4 LogLuvEncode(in vec3 rgb) {
    vec4 result;
    vec3 Xp_Y_XYZp = max(logLuvM * rgb, EPS);
    result.xy = Xp_Y_XYZp.xy / Xp_Y_XYZp.z;

    float Le = 2.0 * log2(Xp_Y_XYZp.y) + 127.0;

    result.w = fract(Le);
    result.z = (Le - (floor(result.w * 255.0)) * r255) * r255;
    return result;
}

vec3 LogLuvDecode(in vec4 logLuv) {
    float Le = logLuv.z * 255.0 + logLuv.w;

    vec3 Xp_Y_XYZp;
    Xp_Y_XYZp.y = exp2((Le - 127.0) * 0.5);
    Xp_Y_XYZp.z = Xp_Y_XYZp.y / logLuv.y;
    Xp_Y_XYZp.x = logLuv.x * Xp_Y_XYZp.z;

    return max0(logLuvInverseM * Xp_Y_XYZp);
}

uint LogLuvEncodeU(in vec3 data) {
    return packUnorm4x8(LogLuvEncode(data));
}

vec3 LogLuvDecodeU(in uint data) {
    return LogLuvDecode(unpackUnorm4x8(data));
}