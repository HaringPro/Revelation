const float PI 			    = 3.14159265359;
const float hPI 		    = 1.57079632679;
const float rPI 		    = 0.31830988618;
const float TAU 		    = 6.28318530718;
const float rTAU 		    = 0.15915494310;
const float rLOG2 		    = 1.44269504089;
const float PHI 		    = 0.61803398875;
const float goldenAngle     = 2.39996322973;

const float EPS 	        = 0.000001;

const float rcp255 		    = 0.00392156863;

const float FP16_MIN        = 6.10e-05;
const float FP16_MAX        = 65504.0;

#define FLT_MAX             uintBitsToFloat(0x7F7FFFFFu)
#define FLT_MIN             uintBitsToFloat(0x00800000u)
#define FLT_POS_INF         uintBitsToFloat(0x7F800000u)
#define FLT_NEG_INF         uintBitsToFloat(0xFF800000u)

//================================================================================================//

#define rcp(x) 			    (1.0 / (x))
#define oms(x) 	 		    (1.0 - (x))
#define max0(x) 		    max(x, 0.0)
#define min1(x) 		    min(x, 1.0)
#define maxEps(x) 		    max(x, EPS)

#define saturate(x) 	    clamp(x, 0.0, 1.0)
#define satSnorm(x) 	    clamp(x, -1.0, 1.0)

#define hermite(x)          smoothstep(0.0, 1.0, x)

#define transMAD(m, v)	    (mat3(m) * (v) + (m)[3].xyz)
#define diagonal2(m)	    vec2((m)[0].x, (m)[1].y)
#define diagonal3(m)	    vec3((m)[0].x, (m)[1].y, m[2].z)
#define diagonal4(m)	    vec4(diagonal3(m), (m)[2].w)
#define projMAD(m, v)	    (diagonal3(m) * (v) + (m)[3].xyz)

#define uvToTexel(coord)    ivec2((coord) * viewSize)
#define texelToUv(texel)    ((vec2(texel) + 0.5) * viewPixelSize)

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

float sdot(vec2 x) 	 	 { return dot(x, x); }
float sdot(vec3 x) 	 	 { return dot(x, x); }
float sdot(vec4 x) 	 	 { return dot(x, x); }

vec2  sincos(float x)    { return vec2(sin(x), cos(x)); }
vec2  cossin(float x)    { return vec2(cos(x), sin(x)); }

float mean(vec2 v)       { return dot(v, vec2(1.0 / 3.0)); }
float mean(vec3 v)       { return dot(v, vec3(1.0 / 3.0)); }
float mean(vec4 v)       { return dot(v, vec4(1.0 / 3.0)); }

//================================================================================================//

float linearstep(float a, float b, float x) {
	return saturate((x - a) / (b - a));
}

vec2 linearstep(vec2 a, vec2 b, vec2 x) {
	return saturate((x - a) / (b - a));
}

vec3 linearstep(vec3 a, vec3 b, vec3 x) {
	return saturate((x - a) / (b - a));
}

//================================================================================================//

// https://iquilezles.org/articles/functions/
float almostIdentity(float x, float m, float n) {
	if (x > m) return x;
	float a = 2.0 * n - m;
	float b = 2.0 * m - 3.0 * n;
	float t = x / m;
	return (a * t + b) * t * t + n;
}

float almostUnitIdentity(float x) {
	return x * x * (2.0 - x);
}

// Quadratic polynomial smooth-min function from https://www.iquilezles.org/www/articles/smin/smin.htm
float smin(float a, float b, float k) {
	k *= 4.0;
	float h = max0(k - abs(a - b)) / k;
	return min(a, b) - h * h * k * 0.25;
}

//================================================================================================//

// Fast sign functions from GeForceLegend
float signI(float x) {
	return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec2 signI(vec2 x) {
	return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

vec3 signI(vec3 x) {
	return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3F800000u);
}

// = x * sign(y)
float signMul(float x, float y) {
	return uintBitsToFloat(floatBitsToUint(x) ^ (floatBitsToUint(y) & 0x80000000u));
}

vec2 signMul(vec2 x, float y) {
	return uintBitsToFloat(floatBitsToUint(x) ^ (floatBitsToUint(y) & 0x80000000u));
}

vec2 signMul(vec2 x, vec2 y) {
	return uintBitsToFloat(floatBitsToUint(x) ^ (floatBitsToUint(y) & 0x80000000u));
}

vec3 signMul(vec3 x, float y) {
	return uintBitsToFloat(floatBitsToUint(x) ^ (floatBitsToUint(y) & 0x80000000u));
}

vec3 signMul(vec3 x, vec3 y) {
	return uintBitsToFloat(floatBitsToUint(x) ^ (floatBitsToUint(y) & 0x80000000u));
}

// https://www.shadertoy.com/view/wlyXRt
float approxSqrt(float x) { return uintBitsToFloat((floatBitsToUint(x) >> 1) + 0x1FC00000u); }
float sqrtNewton(float x, float guess) { return 0.5 * (guess + x / guess); }
float approxSqrtN1(float x) { return sqrtNewton(x, approxSqrt(x)); }

vec2 approxSqrt(vec2 x) { return vec2(approxSqrt(x.x), approxSqrt(x.y)); }
vec3 approxSqrt(vec3 x) { return vec3(approxSqrt(x.x), approxSqrt(x.y), approxSqrt(x.z)); }

float fastAcos(float x) {
	float a = abs(x);
	float r = (hPI - 0.175394 * a) * sqrt(1.0 - a);

	return x < 0.0 ? PI - r : r;
}

float fastAsin(float x) {
	return hPI - fastAcos(x);
}

vec2 fastAcos(vec2 x) {
	return vec2(fastAcos(x.x), fastAcos(x.y));
}

vec2 fastAsin(vec2 x) {
	return vec2(fastAsin(x.x), fastAsin(x.y));
}

// https://www.desmos.com/calculator/cd3mvg1gfo
float approxExp(float x) { return rcp(x * x - x + 1.0); }

//================================================================================================//

float cubicLength(vec2 v) {
	vec2 t = abs(cube(v));
	return pow(t.x + t.y, 1.0 / 3.0);
}

float quarticLength(vec2 v) {
	return sqrt(sqrt(pow4(v.x) + pow4(v.y)));
}

//================================================================================================//

vec4 project(mat4 m, vec3 v) {
	return diagonal4(m) * v.xyzz + m[3];
}

vec3 projectAndDivide(mat4 m, vec3 v) {
	return projMAD(m, v) * rcp(m[2].w * v.z + m[3].w);
}

// https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula
vec3 rotate(vec3 v, vec3 a, vec3 b) {
	float cosTheta = dot(a, b);
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
	vec3 k = normalize(cross(a, b)); // Axis of rotation

	return v * cosTheta + cross(k, v) * sinTheta + k * dot(k, v) * oms(cosTheta);
}

vec2 sampleVogelDisk(uint idx, uint num, float phi) {
	float r = approxSqrt((float(idx) + 0.5) / float(num));
	return cossin(idx * goldenAngle + phi) * r;
}

// https://developer.download.nvidia.cn/cg/refract.html
vec3 refract(vec3 i, vec3 n, float eta) {
	float cosi = -dot(i, n);
	float cost2 = 1.0 - eta * eta * oms(cosi * cosi);
	if (cost2 < 0.0) return vec3(0.0);

	return eta * i + (eta * cosi - sqrt(abs(cost2))) * n;
}
