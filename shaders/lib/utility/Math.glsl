const float PI 			 = 3.14159265359;
const float hPI 		 = 1.57079632679;
const float rPI 		 = 0.31830988618;
const float TAU 		 = 6.28318530718;
const float rTAU 		 = 0.15915494310;
const float rLOG2 		 = 1.44269504089;
const float PHI 		 = 0.61803398875;
const float EPS 	     = 0.000001;
const float goldenAngle  = 2.39996322973;

const float r255 		 = 0.00392156863;
const float r240		 = 0.00416666667;

const float max8f		 = 255.0;
const float max16f		 = 65535.0;
const float max32f		 = 4294967295.0;

//================================================================================================//

#define rcp(x) 			 (1.0 / (x))
#define oms(x) 	 		 (1.0 - (x))
#define fastExp(x) 		 exp2((x) * rLOG2)
#define max0(x) 		 max(x, 0.0)
#define min1(x) 		 min(x, 1.0)
#define maxEps(x) 		 max(x, EPS)

#define saturate(x) 	 clamp(x, 0.0, 1.0)
#define satSnorm(x) 	 clamp(x, -1.0, 1.0)
#define satU8f(x) 		 clamp(x, 0.0, max8f)
#define satS8f(x) 		 clamp(x, -max8f, max8f)
#define satU16f(x) 		 clamp(x, 0.0, max16f)
#define satS16f(x) 		 clamp(x, -max16f, max16f)
#define satU32f(x) 		 clamp(x, 0.0, max32f)
#define satS32f(x) 		 clamp(x, -max32f, max32f)

#define transMAD(m, v)	 (mat3(m) * (v) + (m)[3].xyz)
#define diagonal2(m)	 vec2((m)[0].x, (m)[1].y)
#define diagonal3(m)	 vec3((m)[0].x, (m)[1].y, m[2].z)
#define diagonal4(m)	 vec4(diagonal3(m), (m)[2].w)
#define projMAD(m, v)	 (diagonal3(m) * (v) + (m)[3].xyz)

#define uvToTexel(coord) ivec2((coord) * viewSize)
#define texelToUv(texel) ((vec2(texel) + 0.5) * viewPixelSize)

//================================================================================================//

float maxOf(vec2 v)   	 { return max(v.x, v.y); }
float maxOf(vec3 v)   	 { return max(v.x, max(v.y, v.z)); }
float maxOf(vec4 v)   	 { return max(v.x, max(v.y, max(v.z, v.w))); }
float minOf(vec2 v)   	 { return min(v.x, v.y); }
float minOf(vec3 v)   	 { return min(v.x, min(v.y, v.z)); }
float minOf(vec4 v)   	 { return min(v.x, min(v.y, min(v.z, v.w))); }

float sqr(float x)    	 { return x * x; }
vec2  sqr(vec2 x)	  	 { return x * x; }
vec3  sqr(vec3 x)	  	 { return x * x; }
vec4  sqr(vec4 x)	  	 { return x * x; }

float pow1d5(float x) 	 { return x * x * inversesqrt(x); }
vec3  pow1d5(vec3 x) 	 { return x * x * inversesqrt(x); }

float cube(float x)   	 { return x * x * x; }
vec2  cube(vec2 x)	  	 { return x * x * x; }
vec3  cube(vec3 x)	  	 { return x * x * x; }

float pow4(float x)   	 { x *= x; return x * x; }
vec3  pow4(vec3 x)	  	 { x *= x; return x * x; }

float pow5(float x)   	 { return pow4(x) * x; }
vec3  pow5(vec3 x)	  	 { return pow4(x) * x; }

float pow8(float x)   	 { x *= x; x *= x; return x * x; }

float pow16(float x)	 { x *= x; x *= x; x *= x; return x * x; }

float pow32(float x)	 { x *= x; x *= x; x *= x; x *= x; return x * x; }

float sqrt2(float c)  	 { return sqrt(c * inversesqrt(c)); }
vec3  sqrt2(vec3 c)	  	 { return sqrt(c * inversesqrt(c)); }

float curve(float x)  	 { return sqr(x) * (3.0 - 2.0 * x); }
vec2  curve(vec2 x)	  	 { return sqr(x) * (3.0 - 2.0 * x); }
vec3  curve(vec3 x)	  	 { return sqr(x) * (3.0 - 2.0 * x); }

float sdot(vec2 x) 	 	 { return dot(x, x); }
float sdot(vec3 x) 	 	 { return dot(x, x); }

vec2  sincos(float x)    { return vec2(sin(x), cos(x)); }
vec2  cossin(float x)    { return vec2(cos(x), sin(x)); }

float mean(vec3 v)       { return dot(v, vec3(1.0 / 3.0)); }

float remap(float e0, float e1, float x) { return saturate((x - e0) * rcp(e1 - e0)); }
vec3  remap(float e0, float e1, vec3 x)  { return saturate((x - e0) * rcp(e1 - e0)); }

//================================================================================================//

// https://iquilezles.org/articles/functions/
float almostIdentity(in float x, in float m, in float n) {
    if (x > m) return x;
    float a = 2.0 * n - m;
    float b = 2.0 * m - 3.0 * n;
    float t = x / m;
    return (a * t + b) * t * t + n;
}

float almostUnitIdentity(in float x) {
    return x * x * (2.0 - x);
}

float fastSign(in float x) {
    return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec2 fastSign(in vec2 x) {
    return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec3 fastSign(in vec3 x) {
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

float fastAsin(float x) {
    return hPI - fastAcos(x);
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

float cubeLength(in vec2 v) {
    vec2 t = abs(cube(v));
    return pow(t.x + t.y, 1.0 / 3.0);
}

float quarticLength(in vec2 v) {
	return sqrt2(pow4(v.x) + pow4(v.y));
}

//================================================================================================//

vec3[4] ToSphericalHarmonics(in vec3 value, in vec3 dir) {
	const vec2 k = vec2(sqrt(0.25 * rPI), sqrt(0.75 * rPI));
    float[4] basis = float[4](k.x, k.y * dir.y, k.y * dir.z, k.y * dir.x);

	return vec3[4](value * basis[0], value * basis[1], value * basis[2], value * basis[3]);
}

vec3 FromSphericalHarmonics(in vec3[4] coeff, in vec3 dir) {
	const vec2 k = vec2(sqrt(0.25 * rPI), sqrt(0.75 * rPI));
    float[4] basis = float[4](k.x, k.y * dir.y, k.y * dir.z, k.y * dir.x);

	return coeff[0] * basis[0] + coeff[1] * basis[1] + coeff[2] * basis[2] + coeff[3] * basis[3];
}

//================================================================================================//

mat3 ConstructTBN(in vec3 n) {
	vec3 t = normalize(vec3(abs(n.y) + n.z, 0.0, -n.x));
	vec3 b = normalize(cross(t, n));
	return mat3(t, b, n);
}

mat2 rotateMat(in float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return mat2(cosine, -sine, sine, cosine);
}

mat3 rotateMatX(in float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return mat3(1.0, 0.0, 0.0, 0.0, cosine, -sine, 0.0, sine, cosine);
}

mat3 rotateMatY(in float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return mat3(cosine, 0.0, sine, 0.0, 1.0, 0.0, -sine, 0.0, cosine);
}

mat3 rotateMatZ(in float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return mat3(cosine, -sine, 0.0, sine, cosine, 0.0, 0.0, 0.0, 1.0);
}

// https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula
vec3 rotate(in vec3 v, in vec3 a, in vec3 b) {
	float cosTheta = dot(a, b);
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
	vec3 k = normalize(cross(a, b)); // Axis of rotation

	return v * cosTheta + cross(k, v) * sinTheta + k * dot(k, v) * oms(cosTheta);
}