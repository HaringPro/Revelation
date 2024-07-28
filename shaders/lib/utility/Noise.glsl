const int noiseTextureResolution = 256;
const float noiseTexturePixelSize = 1.0 / noiseTextureResolution;

float Calculate3DNoise(in vec3 position) {
    vec3 p = floor(position);
	vec3 b = curve(position - p);

	vec2 uv = p.xy + b.xy + 97.0 * p.z;
    vec2 rg = texture(noisetex, (uv + 0.5) * noiseTexturePixelSize).xy;

    return mix(rg.x, rg.y, b.z);
}

float bayer2(vec2 a)   { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }

float bayer4(vec2 a)   { return bayer2 (0.5   * a) * 0.25     + bayer2(a); }
float bayer8(vec2 a)   { return bayer4 (0.5   * a) * 0.25     + bayer2(a); }
float bayer16(vec2 a)  { return bayer4 (0.25  * a) * 0.0625   + bayer4(a); }
float bayer32(vec2 a)  { return bayer8 (0.25  * a) * 0.0625   + bayer4(a); }
float bayer64(vec2 a)  { return bayer8 (0.125 * a) * 0.015625 + bayer8(a); }
float bayer128(vec2 a) { return bayer16(0.125 * a) * 0.015625 + bayer8(a); }

float hash1(vec2 p) {
	vec3 p3  = fract(vec3(p.xyx) * 443.897);
    p3 += dot(p3, p3.zyx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

float hash1(vec3 p3) {
	p3  = fract(p3 * 443.897);
    p3 += dot(p3, p3.zyx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec3 p3) {
	p3 = fract(p3 * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.xx + p3.yz) * p3.zy);
}

uint triple32(uint x) {
    // https://nullprogram.com/blog/2018/07/31/
    x ^= x >> 17;
    x *= 0xed5ad4bbu;
    x ^= x >> 11;
    x *= 0xac4c1b51u;
    x ^= x >> 15;
    x *= 0x31848babu;
    x ^= x >> 14;
    return x;
}

#if defined RANDOM_NOISE
uint randState = triple32(uint(gl_FragCoord.x + viewWidth * gl_FragCoord.y) + uint(viewWidth * viewHeight) * frameCounter);
uint RandNext() { return randState = triple32(randState); }
//#define RandNext2()  	uvec2(RandNext(), RandNext())
//#define RandNext3()  	uvec3(RandNext2(), RandNext())
//#define RandNext4()  	uvec4(RandNext3(), RandNext())
#define RandNextF()  	(float(RandNext()) / float(0xffffffffu))
#define RandNext2F() 	(vec2(RandNext()) / float(0xffffffffu))
//#define RandNext3F() 	(vec3(RandNext3()) / float(0xffffffffu))
//#define RandNext4F() 	(vec4(RandNext4()) / float(0xffffffffu))
#endif

// http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
const float PHI2 = 1.32471795724;
const float PHI3 = 1.22074408460;

float R1(in int n, in float seed) {
	return fract(seed + n * PHI);
}

vec2 R2(in int n, in vec2 seed) {
    const vec2 alpha = 1.0 / vec2(PHI2, PHI2 * PHI2);
	return fract(seed + n * alpha);
}

vec3 R3(in int n, in vec3 seed) {
    const vec3 alpha = 1.0 / vec3(PHI3, PHI3 * PHI3, PHI3 * PHI3 * PHI3);
	return fract(seed + n * alpha);
}

vec2 R2(in float n) {
	const vec2 alpha = 1.0 / vec2(PHI2, PHI2 * PHI2);
	return fract(0.5 + n * alpha);
}

float BlueNoise(in ivec2 texel) {
	return texelFetch(noisetex, texel & 255, 0).a;
}

float BlueNoiseTemporal(in ivec2 texel) {
	#ifdef TAA_ENABLED
		return R1(frameCounter % 256, texelFetch(noisetex, texel & 255, 0).a);
	#else
		return texelFetch(noisetex, texel & 255, 0).a;
	#endif
}

float Bayer64Temporal(in vec2 coord) {
	#ifdef TAA_ENABLED
		return R1(frameCounter % 256, bayer64(coord));
	#else
		return bayer8(0.125 * coord) * 0.015625 + bayer8(coord);
	#endif
}

float InterleavedGradientNoise(in vec2 coord) {
	return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y));
}

float InterleavedGradientNoiseTemporal(in vec2 coord) {
	#ifdef TAA_ENABLED
		return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y + 0.00623715 * (frameCounter & 63)));
	#else
		return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y));
	#endif
}

// From Peter Shirley's 'Realistic Ray Tracing (2nd Edition)' book, pg. 60
float TentFilter(in float x) {
	return (x < 0.5) ? sqrt(2.0 * x) - 1.0 : 1.0 - sqrt(2.0 - (2.0 * x));
}

vec2 TentFilter(in vec2 x) {
	return vec2(TentFilter(x.x), TentFilter(x.y));
}
