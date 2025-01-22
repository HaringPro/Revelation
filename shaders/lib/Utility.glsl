/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/


#include "/settings.glsl"

const float PI 			= 3.14159265359;
const float hPI 		= 1.57079632679;
const float rPI 		= 0.31830988618;
const float TAU 		= 6.28318530718;
const float rTAU 		= 0.15915494310;
const float rLOG2 		= 1.44269504089;
const float PHI 		= 0.61803398875;
//const float EPS 	    = 1e-6;
const float goldenAngle = 2.39996322973;

const float r255 		= 0.00392156863;
const float r240		= 0.00416666667;

#define rcp(x) 			(1.0 / (x))
#define oneMinus(x) 	(1.0 - (x))
#define fastExp(x) 		exp2((x) * rLOG2)
#define max0(x) 		max(x, 0.0)
#define min1(x) 		min(x, 1.0)
#define maxEps(x) 		max(x, 1e-6)
#define saturate(x) 	clamp(x, 0.0, 1.0)
#define clamp16f(x) 	clamp(x, 0.0, 65535.0)

#define transMAD(m, v)	(mat3(m) * (v) + (m)[3].xyz)
#define diagonal2(m)	vec2((m)[0].x, (m)[1].y)
#define diagonal3(m)	vec3((m)[0].x, (m)[1].y, m[2].z)
#define diagonal4(m)	vec4(diagonal3(m), (m)[2].w)
#define projMAD(m, v)	(diagonal3(m) * (v) + (m)[3].xyz)

#define uvToTexel(coord) ivec2((coord) * viewSize)
#define texelToUv(texel) ((vec2(texel) + 0.5) * viewPixelSize)

float maxOf(vec2 v)   	{ return max(v.x, v.y); }
float maxOf(vec3 v)   	{ return max(v.x, max(v.y, v.z)); }
float maxOf(vec4 v)   	{ return max(v.x, max(v.y, max(v.z, v.w))); }
float minOf(vec2 v)   	{ return min(v.x, v.y); }
float minOf(vec3 v)   	{ return min(v.x, min(v.y, v.z)); }
float minOf(vec4 v)   	{ return min(v.x, min(v.y, min(v.z, v.w))); }

float sqr(float x)    	{ return x * x; }
vec2  sqr(vec2 x)	  	{ return x * x; }
vec3  sqr(vec3 x)	  	{ return x * x; }
vec4  sqr(vec4 x)	  	{ return x * x; }

float pow1d5(float x) 	{ return x * x * inversesqrt(x); }
vec3  pow1d5(vec3 x) 	{ return x * x * inversesqrt(x); }

float cube(float x)   	{ return x * x * x; }
vec2  cube(vec2 x)	  	{ return x * x * x; }
vec3  cube(vec3 x)	  	{ return x * x * x; }

float pow4(float x)   	{ x *= x; return x * x; }
vec3  pow4(vec3 x)	  	{ x *= x; return x * x; }

float pow5(float x)   	{ return pow4(x) * x; }
vec3  pow5(vec3 x)	  	{ return pow4(x) * x; }

float pow8(float x)   	{ x *= x; x *= x; return x * x; }

float pow16(float x)	{ x *= x; x *= x; x *= x; return x * x; }

float pow32(float x)	{ x *= x; x *= x; x *= x; x *= x; return x * x; }

float sqrt2(float c)  	{ return sqrt(c * inversesqrt(c)); }
vec3  sqrt2(vec3 c)	  	{ return sqrt(c * inversesqrt(c)); }

float curve(float x)  	{ return sqr(x) * (3.0 - 2.0 * x); }
vec2  curve(vec2 x)	  	{ return sqr(x) * (3.0 - 2.0 * x); }
vec3  curve(vec3 x)	  	{ return sqr(x) * (3.0 - 2.0 * x); }

float dotSelf(vec2 x) 	{ return dot(x, x); }
float dotSelf(vec3 x) 	{ return dot(x, x); }

vec2  sincos(float x)   { return vec2(sin(x), cos(x)); }
vec2  cossin(float x)   { return vec2(cos(x), sin(x)); }

float remap(float e0, float e1, float x) { return saturate((x - e0) * rcp(e1 - e0)); }
vec3  remap(float e0, float e1, vec3 x)  { return saturate((x - e0) * rcp(e1 - e0)); }

float mean(vec3 v) { return dot(v, vec3(1.0 / 3.0)); }

// https://iquilezles.org/articles/functions/
// float almostIdentity(float x, float m, float n) {
//     if (x > m) return x;
//     float a = 2.0 * n - m;
//     float b = 2.0 * m - 3.0 * n;
//     float t = x / m;
//     return (a * t + b) * t * t + n;
// }

// float almostUnitIdentity(float x) {
//     return x * x * (2.0 - x);
// }

float fastSign(float x) {
    return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec2 fastSign(vec2 x) {
    return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec3 fastSign(vec3 x) {
    return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

// https://www.shadertoy.com/view/wlyXRt
float approxSqrt(in float x) { return uintBitsToFloat((floatBitsToUint(x) >> 1) + 0x1FC00000u); }
float sqrtNewton(float x, float guess) { return 0.5 * (guess + x / guess); }
float approxSqrtN1(in float x) { return sqrtNewton(x, approxSqrt(x)); }

float fastAcos(in float x) {
    float a = abs(x);
	float r = (hPI - 0.175394 * a) * sqrt(1.0 - a);

	return x < 0.0 ? PI - r : r;
}

/*
// Handbook of Mathematical Functions
// M. Abramowitz and I.A. Stegun, Ed.
// Absolute error <= 6.7e-5
// Source: https://web.archive.org/web/20161223122122/http://http.developer.nvidia.com:80/Cg/acos.html
float FastAcos(in float x) {
	float negate = float(x < 0.0);
	x = abs(x);
	float ret = -0.0187293;
	ret = ret * x;
	ret = ret + 0.0742610;
	ret = ret * x;
	ret = ret - 0.2121144;
	ret = ret * x;
	ret = ret + 1.5707288;
	ret = ret * sqrt(1.0 - x);
	ret = ret - 2.0 * negate * ret;
	return negate * PI + ret;
}
*/

// https://www.desmos.com/calculator/cd3mvg1gfo
float approxExp(in float x) { return rcp(x * x - x + 1.0); }

vec2 ToSphereMap(in vec3 dir) {
    return vec2(atan(-dir.x, -dir.z) * rTAU + 0.5, fastAcos(dir.y) * rPI);
}

vec3 FromSphereMap(in vec2 coord) {
    coord.y *= PI;
    return vec3(sincos(coord.x * TAU) * sin(coord.y), cos(coord.y)).xzy;
}

mat3 ConstructTBN(in vec3 n) {
	vec3 t = normalize(vec3(abs(n.y) + n.z, 0.0, -n.x));
	vec3 b = normalize(cross(t, n));
	return mat3(t, b, n);
}

#if defined NORMAL_MAPPING
	void DecodeNormalTex(inout vec3 normalTex) {
        if (any(greaterThan(normalTex, vec3(0.003)))) {
			normalTex = normalTex * 2.0 - 1.0 + r255;
			#if TEXTURE_FORMAT == 0
				normalTex.z = sqrt(saturate(oneMinus(dotSelf(normalTex.xy))));
			#else
				normalTex = normalize(normalTex);
			#endif
    		normalTex.xy = uintBitsToFloat(floatBitsToUint(max0(abs(normalTex.xy) - r255)) ^ (floatBitsToUint(normalTex.xy) & 0x80000000u));
		}
	}
#endif

float Packup2x8(in vec2 data) {
	return dot(floor(data * 255.0 + 0.5), vec2(256.0 / 65535.0, 1.0 / 65535.0));
}

float PackupDithered2x8(in vec2 data, in float dither) {
	return dot(floor(data * 255.0 + dither), vec2(256.0 / 65535.0, 1.0 / 65535.0));
}

vec2 Unpack2x8(in float data) {
	float x, y = modf(data * (65535.0 / 256.0), x) * 256.0;
	return vec2(x, y) * r255;
}

float Packup2x8X(in float data) { return floor(data * (65535.0 / 256.0)) * r255; }
float Packup2x8Y(in float data) { return fract(data * (65535.0 / 256.0)) * (256.0 * r255); }

uint Packup2x8U(in vec2 data) {
	uvec2 u = uvec2(data * 255.0 + 0.5);
	return (u.x << 8) | u.y;
}

uint PackupDithered2x8U(in vec2 data, in float dither) {
	uvec2 u = uvec2(data * 255.0 + dither);
	return (u.x << 8) | u.y;
}

vec2 Unpack2x8U(in uint data) {
	return vec2(float(data >> 8), float(data & 0xFF)) * r255;
}

float Unpack2x8UX(in uint data) { return float(data >> 8) * r255; }
float Unpack2x8UY(in uint data) { return float(data & 0xFF) * r255; }

// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/packing.glsl

// Octahedral Unit Vector encoding
// Intuitive, fast, and has very little error.
vec2 encodeUnitVector(in vec3 vector) {
	// Scale down to octahedron, project onto XY plane
    vector.xy /= dot(vec3(1.0), abs(vector));
	// Reflect -Z hemisphere folds over the diagonals
	vec2 encoded = vector.z <= 0.0 ? (1.0 - abs(vector.yx)) * vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0) : vector.xy;
	// Scale to [0, 1]
	return encoded * 0.5 + 0.5;
}

vec3 decodeUnitVector(in vec2 encoded) {
	// Scale to [-1, 1]
	encoded = encoded * 2.0 - 1.0;
	// Exctract Z component
	vec3 vector = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
	// Reflect -Z hemisphere folds over the diagonals
	float t = max(-vector.z, 0.0);
	vector.xy += vec2(vector.x >= 0.0 ? -t : t, vector.y >= 0.0 ? -t : t);
	// Normalize and return
	return normalize(vector);
}

vec3 linearToSRGB(in vec3 color) {
	return mix(color * 12.92, 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055, lessThan(vec3(0.0031308), color));
}

vec3 sRGBtoLinear(in vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), lessThan(vec3(0.04045), color));
}

float GetLuminance(in vec3 color) {
	//return dot(color, vec3(0.2722287168, 0.6740817658, 0.0536895174));
	return dot(color, vec3(0.2722, 0.6741, 0.0537));
}

vec3 colorSaturation(in vec3 color, in const float sat) { return mix(vec3(GetLuminance(color)), color, sat); }

// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/blackbody.glsl
vec3 plancks(in float t, in vec3 lambda) {
    const float h = 6.63e-16;
    const float c = 3.0e17;
    const float k = 1.38e-5;
    vec3 p1 = (2.0 * h * sqr(c)) / pow5(lambda);
    vec3 p2 = fastExp(h * c / (lambda * k * t)) - vec3(1.0);
    return (p1 / p2) * 1e18;
}

vec3 blackbody(in float t) {
    vec3 rgb = plancks(t, vec3(660.0, 550.0, 440.0));
         rgb = rgb / max(rgb.x, max(rgb.y, rgb.z));

    return rgb;
}

vec4 textureSmoothFilter(in sampler2D tex, in vec2 coord) {
	// From https://iquilezles.org/www/articles/texture/texture.htm
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res + 0.5;

	vec2 i, f = modf(coord, i);
	f *= f * f * (f * (f * 6.0 - 15.0) + 10.0);
	coord = i + f;

	coord = (coord - 0.5) / res;
	return textureLod(tex, coord, 0.0);
}

vec4 cubic(in float x) {
    float x2 = x * x;
    float x3 = x2 * x;
    vec4 w;
    w.x = -x3 + 3.0 * x2 - 3.0 * x + 1.0;
    w.y = 3.0 * x3 - 6.0 * x2 + 4.0;
    w.z = -3.0 * x3 + 3.0 * x2 + 3.0 * x + 1.0;
    w.w = x3;
    return w * rcp(6.0);
}

vec4 textureBicubic(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res - 0.5;

	vec2 fTexel = fract(coord);
	coord -= fTexel;

    vec4 xCubic = cubic(fTexel.x);
    vec4 yCubic = cubic(fTexel.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;

	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

    vec4 offset = c + vec4(xCubic.yw, yCubic.yw) / s;
	offset *= 1.0 / res.xxyy;

	vec4 sample0 = textureLod(tex, offset.xz, 0.0);
	vec4 sample1 = textureLod(tex, offset.yz, 0.0);
	vec4 sample2 = textureLod(tex, offset.xw, 0.0);
	vec4 sample3 = textureLod(tex, offset.yw, 0.0);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}
/*
vec4 textureBicubicLod(in sampler2D tex, in vec2 coord, in int lod) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res - 0.5;

	vec2 fTexel = fract(coord);
	coord -= fTexel;

    vec4 xCubic = cubic(fTexel.x);
    vec4 yCubic = cubic(fTexel.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;

	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

    vec4 offset = c + vec4(xCubic.yw, yCubic.yw) / s;
	offset *= 1.0 / res.xxyy;

	vec4 sample0 = textureLod(tex, offset.xz, lod);
	vec4 sample1 = textureLod(tex, offset.yz, lod);
	vec4 sample2 = textureLod(tex, offset.xw, lod);
	vec4 sample3 = textureLod(tex, offset.yw, lod);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec4 textureSmooth(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	coord = coord * res - 0.5;

    vec2 p = floor(coord);

	vec2 pixelSize = 1.0 / res;
    vec4 sample0 = textureLod(tex, (p                 ) * pixelSize, 0.0);
    vec4 sample1 = textureLod(tex, (p + vec2(1.0, 0.0)) * pixelSize, 0.0);
    vec4 sample2 = textureLod(tex, (p + vec2(0.0, 1.0)) * pixelSize, 0.0);
    vec4 sample3 = textureLod(tex, (p + vec2(1.0, 1.0)) * pixelSize, 0.0);

    vec2 f = fract(coord);
    return mix(mix(sample0, sample1, f.x), mix(sample2, sample3, f.x), f.y);
}
*/

//================================================================================================//

struct FogData {
	vec3 scattering;
	vec3 transmittance;
};

#define ApplyFog(scene, fog) ((scene) * fog.transmittance + fog.scattering)

//================================================================================================//

#define COMBINED_TEXTURE_SAMPLER 	colortex0

#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#define loadDepth1(texel) 			texelFetch(depthtex1, texel, 0).x

#define loadSceneColor(texel) 		texelFetch(colortex0, texel, 0).rgb

#define loadAlbedo(texel) 			texelFetch(colortex6, texel, 0).rgb
#define loadGbufferData0(texel) 	texelFetch(colortex7, texel, 0)
#define loadGbufferData1(texel) 	texelFetch(colortex8, texel, 0)

#if defined DISTANT_HORIZONS
	#define loadDepth0DH(texel) 	texelFetch(dhDepthTex0, texel, 0).x
	#define loadDepth1DH(texel)		texelFetch(dhDepthTex1, texel, 0).x
#endif

//================================================================================================//

#ifdef DEBUG_RESHADING
	uniform float dyn_100;
	uniform float dyn_101;
	uniform float dyn_102;
	uniform float dyn_103;
	uniform float dyn_104;
	uniform float dyn_105;
	uniform float dyn_106;
	uniform float dyn_107;
#endif
