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
const float goldenAngle = 2.39996322973;

//const float EPS 	    = 1e-6;
const float r255 		= 0.00392156863;
const float r240		= 0.00416666667;

#define rcp(x) 			(1.0 / (x))
#define oneMinus(x) 	(1.0 - (x))
#define fastExp(x) 		exp2((x) * rLOG2)
#define max0(x) 		max(x, 0.0)
#define maxEps(x) 		max(x, 1e-6)
#define saturate(x) 	clamp(x, 0.0, 1.0)
#define clamp16f(x) 	clamp(x, 0.0, 65535.0)

#define transMAD(m, v)	(mat3(m) * (v) + (m)[3].xyz)
#define diagonal2(m)	vec2((m)[0].x, (m)[1].y)
#define diagonal3(m)	vec3((m)[0].x, (m)[1].y, m[2].z)
#define diagonal4(m)	vec4(diagonal3(m), (m)[2].w)
#define projMAD(m, v)	(diagonal3(m) * (v) + (m)[3].xyz)

#define rawCoord(coord) ivec2((coord) * viewSize)

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

float cube(float x)   	{ return x * x * x; }
vec2  cube(vec2 x)	  	{ return x * x * x; }
vec3  cube(vec3 x)	  	{ return x * x * x; }

float pow4(float x)   	{ return cube(x) * x; }
vec3  pow4(vec3 x)	  	{ return cube(x) * x; }

float pow5(float x)   	{ return pow4(x) * x; }
vec3  pow5(vec3 x)	  	{ return pow4(x) * x; }

float pow16(float x)   	{ return sqr(pow4(x)); }

float sqrt2(float c)  	{ return sqrt(sqrt(c)); }
vec3  sqrt2(vec3 c)	  	{ return sqrt(sqrt(c)); }

float curve(float x)  	{ return sqr(x) * (3.0 - 2.0 * x); }
vec2  curve(vec2 x)	  	{ return sqr(x) * (3.0 - 2.0 * x); }
vec3  curve(vec3 x)	  	{ return sqr(x) * (3.0 - 2.0 * x); }

float dotSelf(vec2 x) 	{ return dot(x, x); }
float dotSelf(vec3 x) 	{ return dot(x, x); }

vec2  sincos(float x)   { return vec2(sin(x), cos(x)); }
vec2  cossin(float x)   { return vec2(cos(x), sin(x)); }

float remap(float e0, float e1, float x) { return saturate((x - e0) / (e1 - e0)); }

// https://www.shadertoy.com/view/wlyXRt
float fastSqrt(in float x) { return uintBitsToFloat((floatBitsToUint(x) >> 1) + 0x1FC00000u); }
float sqrtNewton(float x, float guess) { return 0.5 * (guess + x / guess); }
float fastSqrtN1(in float x) { return sqrtNewton(x, fastSqrt(x)); }

float fastAcos(in float x) {
    float a = abs(x);
	float r = (hPI - 0.175394 * a) * sqrt(1.0 - a);

	return x < 0.0 ? PI - r : r;
}

#if defined MC_NORMAL_MAP
	void DecodeNormalTex(inout vec3 normalTex) {
        if (all(lessThan(normalTex, vec3(0.003)))) return;
		normalTex = normalTex * 2.0 - oneMinus(r255);
		#if TEXTURE_FORMAT == 0
			normalTex.z = sqrt(saturate(oneMinus(dotSelf(normalTex.xy))));
		#else
			normalTex = normalize(normalTex);
		#endif
		//normalTex.xy = max0(abs(normalTex.xy) - r255) * sign(normalTex.xy);
	}
#endif

// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/packing.glsl

// Octahedral Unit Vector encoding
// Intuitive, fast, and has very little error.
vec2 encodeUnitVector(in vec3 vector) {
	// Scale down to octahedron, project onto XY plane
	vector.xy /= abs(vector.x) + abs(vector.y) + abs(vector.z);
	// Reflect -Z hemisphere folds over the diagonals
	vec2 encoded = vector.z <= 0.0 ? (1.0 - abs(vector.yx)) * vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0) : vector.xy;
	// Scale to [0, 1]
	return encoded * 0.5 + 0.5;
}

vec3 decodeUnitVector(in vec2 encoded) {
	// Scale to [-1, 1]
	encoded = (encoded - 0.5) * 2.0;
	// Exctract Z component
	vec3 vector = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
	// Reflect -Z hemisphere folds over the diagonals
	float t = max(-vector.z, 0.0);
	vector.xy += vec2(vector.x >= 0.0 ? -t : t, vector.y >= 0.0 ? -t : t);
	// Normalize and return
	return normalize(vector);
}

float packUnorm2x8(in vec2 xy) {
	return dot(floor(255.0 * xy + 0.5), vec2(1.0 / 65535.0, 256.0 / 65535.0));
}

float packUnorm2x8(in float x, in float y) { return packUnorm2x8(vec2(x, y)); }

float packUnorm2x8Dithered(in vec2 xy, in float dither) {
	return dot(floor(255.0 * xy + dither), vec2(1.0 / 65535.0, 256.0 / 65535.0));
}

vec2 unpackUnorm2x8(in float pack) {
	vec2 xy; xy.x = modf(pack * 65535.0 / 256.0, xy.y);
	return xy * vec2(256.0 * r255, r255);
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
	// from https://iquilezles.org/www/articles/texture/texture.htm
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
	vec2 res = textureSize(tex, 0);

	coord = coord * res - 0.5;

	vec2 fTexel = fract(coord);
	coord -= fTexel;

    vec4 xCubic = cubic(fTexel.x);
    vec4 yCubic = cubic(fTexel.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;

	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

    vec4 offset = c + vec4(xCubic.y, xCubic.w, yCubic.y, yCubic.w) / s;
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
	vec2 res = textureSize(tex, lod);

	coord = coord * res - 0.5;

	vec2 fTexel = fract(coord);
	coord -= fTexel;

    vec4 xCubic = cubic(fTexel.x);
    vec4 yCubic = cubic(fTexel.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;

	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

    vec4 offset = c + vec4(xCubic.y, xCubic.w, yCubic.y, yCubic.w) / s;
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
	vec2 res = textureSize(tex, 0);
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