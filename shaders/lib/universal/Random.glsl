const int noiseTextureResolution = 256;
const float noiseTexturePixelSize = 1.0 / noiseTextureResolution;

float Pseudo3DNoise(vec3 pos) {
	vec3 p = floor(pos);
	vec3 b = hermite(pos - p);

	vec2 uv = p.xy + b.xy + 97.0 * p.z;
	vec2 rg = texture(noisetex, (uv + 0.5) * noiseTexturePixelSize).xy;

	return mix(rg.x, rg.y, b.z);
}

//================================================================================================//

// Hash without Sine
// https://www.shadertoy.com/view/4djSRW
float hash11(float p) {
	p = fract(p * .1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p) {
	vec3 p3 = fract(p.xyx * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * .1031);
	p3 += dot(p3, p3.zyx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash21(float p) {
	vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(p.xyx * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 hash23(vec3 p3) {
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash31(float p) {
vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

vec3 hash32(vec2 p) {
	vec3 p3 = fract(p.xyx * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

//================================================================================================//

// A perfect integer hash function from https://nullprogram.com/blog/2018/07/31/
uint triple32(uint x) {
	// exact bias: 0.020888578919738908
	x ^= x >> 17;
	x *= 0xed5ad4bbu;
	x ^= x >> 11;
	x *= 0xac4c1b51u;
	x ^= x >> 15;
	x *= 0x31848babu;
	x ^= x >> 14;
	return x;
}

// https://www.pcg-random.org/
uint pcg(inout uint state) {
    state = state * 747796405u + 2891336453u;
    uint result = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (result >> 22u) ^ result;
}

float nextFloat(inout uint state) {
    return float(pcg(state)) * rcp(4294967295.0);
}

vec2 nextVec2(inout uint state) {
    return vec2(nextFloat(state), nextFloat(state));
}

uint initRandomState(uvec2 texelIndex, uint frameIndex) {
	return triple32(EncodeMorton2D(texelIndex)) + frameIndex;
}

//================================================================================================//

// Rn sequence from http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
float R1(int n) {
	const float g = 1.6180339887498948482;
	const float a = 1.0 / g;
	return fract(0.5 + n * a);
}

float R1(int n, float seed) {
	const float g = 1.6180339887498948482;
	const float a = 1.0 / g;
	return fract(seed + n * a);
}

vec2 R2(int n) {
	const float g = 1.32471795724474602596;
	const vec2 a = 1.0 / vec2(g, g * g);
	return fract(0.5 + n * a);
}

vec2 R2(int n, vec2 seed) {
	const float g = 1.32471795724474602596;
	const vec2 a = 1.0 / vec2(g, g * g);
	return fract(seed + n * a);
}

vec3 R3(int n) {
	const float g = 1.22074408460575947536;
	const vec3 a = 1.0 / vec3(g, g * g, g * g * g);
	return fract(0.5 + n * a);
}

vec3 R3(int n, vec3 seed) {
	const float g = 1.22074408460575947536;
	const vec3 a = 1.0 / vec3(g, g * g, g * g * g);
	return fract(seed + n * a);
}

vec2 R2(float n) {
	const float g = 1.32471795724474602596;
	const vec2 a = 1.0 / vec2(g, g * g);
	return fract(0.5 + n * a);
}

//================================================================================================//

// Blue Noise
float BlueNoise(ivec2 texel) {
	return texelFetch(noisetex, texel & 255, 0).a;
}

float BlueNoise(ivec2 texel, int frame) {
	#if defined(TAA_ENABLED) || SR_ENABLE
		return R1(frame, texelFetch(noisetex, texel & 255, 0).a);
	#else
		return texelFetch(noisetex, texel & 255, 0).a;
	#endif
}

// Spatiotemporal Blue Noise
float SampleStbnVec1(ivec2 texel, int frame) {
	return texelFetch(stbnVec1Tex, ivec3(texel, frame) & ivec3(127, 127, 63), 0).x;
}

vec2 SampleStbnVec2(ivec2 texel, int frame) {
	return texelFetch(stbnVec2Tex, ivec3(texel, frame) & ivec3(127, 127, 63), 0).xy;
}

vec2 SampleStbnUnitvec2(ivec2 texel, int frame) {
	return texelFetch(stbnUnitvec2Tex, ivec3(texel, frame) & ivec3(127, 127, 63), 0).xy;
}

//================================================================================================//

// Interleaved Gradient Noise
// https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
// https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
float InterleavedGradientNoise(vec2 coord) {
	return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y));
}

float InterleavedGradientNoise(vec2 coord, int frame) {
	#if defined(TAA_ENABLED) || SR_ENABLE
		coord += 5.588238 * float(frame % 64);
	#endif
	return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y));
}

//================================================================================================//

// From Peter Shirley's 'Realistic Ray Tracing (2nd Edition)' book, pg. 60
float TentFilter(float x) {
	return (x < 0.5) ? sqrt(2.0 * x) - 1.0 : 1.0 - sqrt(2.0 - (2.0 * x));
}

vec2 TentFilter(vec2 x) {
	return vec2(TentFilter(x.x), TentFilter(x.y));
}

// https://graphics-programming.org/blog/ordered-dithering-is-useful-and-good
float dither256x256(uvec2 fragCoord) {
    uint x = fragCoord.x ^ fragCoord.y;
    uint y = fragCoord.y;
    uint z = x << 16 | y;
    z |= z << 12;
    z &= 0xF0F0F0F0u;
    z |= z >> 6;
    z &= 0x33333333u;
    z |= z << 3;
    z &= 0xaaaaaaaau;
    z  = z >> 9 | z << 6;
    z &= 0x7fffffu;
    return uintBitsToFloat(
        floatBitsToUint(1.0) | z
    ) - 1.0;
}

//================================================================================================//

// Halton Sequence
// https://en.wikipedia.org/wiki/Halton_sequence
float Halton(uint b, uint i) {
	float r = 0.0;
	float f = 1.0;
	while (i > 0u) {
		f *= 1.0 / float(b);
		r += f * float(i % b);
		i /= b;
	}
	return r;
}

float Halton2(uint i) {
	return float(bitfieldReverse(i)) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 Halton23(uint i) {
	return vec2(Halton2(i), Halton(3, i));
}

vec2 Halton35(uint i) {
	return vec2(Halton(3, i), Halton(5, i));
}

//================================================================================================//

// Hammersley Sequence
// http://holger.dammertz.org/stuff/notes_HammersleyOnHemisphere.html
float radicalInverse_VdC(uint bits) {
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 Hammersley(uint i, uint N) {
	return vec2(float(i) / float(N), radicalInverse_VdC(i));
}

//================================================================================================//

// Sobol Sequence
// https://www.shadertoy.com/view/sd2Xzm
uvec2 Sobol(uint n) {
	uvec2 p = uvec2(0u);
	uvec2 d = uvec2(0x80000000u);

	for (; n != 0u; n >>= 1u) {
		if ((n & 1u) != 0u)
			p ^= d;

		d.x >>= 1u; // 1st dimension Sobol matrix, is same as base 2 Van der Corput
		d.y ^= d.y >> 1u; // 2nd dimension Sobol matrix
	}

	return p;
}

// EDIT: updated with a new hash that fixes an issue with the old one.
// Details in the post linked at the top.
uint OwenHash(uint x, uint seed) { // Works best with random seeds
	x ^= x * 0x3d20adeau;
	x += seed;
	x *= (seed >> 16) | 1u;
	x ^= x * 0x05526c56u;
	x ^= x * 0x53a22864u;
	return x;
}

uint OwenScramble(uint p, uint seed) {
	p = bitfieldReverse(p);
	p = OwenHash(p, seed);
	return bitfieldReverse(p);
}
