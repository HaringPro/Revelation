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

// Rn sequence from http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
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

/***************************************************************************
 # Copyright (c) 2015-21, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/

/** Utility functions for Morton codes.
    This is using the usual bit twiddling. See e.g.: https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/

    The interleave functions are named based to their output size in bits.
    The deinterleave functions are named based on their input size in bits.
    So, deinterleave_16bit(interleave_16bit(x)) == x should hold true.

    TODO: Make this a host/device shared header, ensure code compiles on the host.
    TODO: Add optimized 8-bit and 2x8-bit interleaving functions.
    TODO: Use NvApi intrinsics to optimize the code on NV.
*/

/** 32-bit bit interleave (Morton code).
    \param[in] v 16-bit values in the LSBs of each component (higher bits don't matter).
    \return 32-bit value.
*/
uint interleave_32bit(uvec2 v)
{
    uint x = v.x & 0x0000ffffu;              // x = ---- ---- ---- ---- fedc ba98 7654 3210
    uint y = v.y & 0x0000ffffu;

    x = (x | (x << 8)) & 0x00FF00FFu;        // x = ---- ---- fedc ba98 ---- ---- 7654 3210
    x = (x | (x << 4)) & 0x0F0F0F0Fu;        // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
    x = (x | (x << 2)) & 0x33333333u;        // x = --fe --dc --ba --98 --76 --54 --32 --10
    x = (x | (x << 1)) & 0x55555555u;        // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0

    y = (y | (y << 8)) & 0x00FF00FFu;
    y = (y | (y << 4)) & 0x0F0F0F0Fu;
    y = (y | (y << 2)) & 0x33333333u;
    y = (y | (y << 1)) & 0x55555555u;

    return x | (y << 1);
}

/** Generates a pair of 32-bit pseudorandom numbers based on a pair of 32-bit values.

    The code uses a 64-bit block cipher, the Tiny Encryption Algorithm (TEA) by Wheeler et al., 1994.
    The 128-bit key is fixed and adapted from here: https://www.ibiblio.org/e-notes/webcl/mc.htm.
    This function can be useful for seeding other pseudorandom number generators.

    \param[in] v0 The first value (low dword of the block).
    \param[in] v1 The second value (high dword of the block).
    \param[in] iterations Number of iterations (the authors recommend 16 at a minimum).
    \return Two pseudorandom numbers (the block cipher of (v0,v1)).
*/
uvec2 blockCipherTEA(uint v0, uint v1)
{
    uint sum = 0u;
    const uint delta = 0x9e3779b9u;
    const uint k[4] = uint[4](0xa341316cu, 0xc8013ea4u, 0xad90777du, 0x7e95761eu); // 128-bit key.
    for (int i = 0; i < 16; i++)
    {
        sum += delta;
        v0 += ((v1 << 4) + k[0]) ^ (v1 + sum) ^ ((v1 >> 5) + k[1]);
        v1 += ((v0 << 4) + k[2]) ^ (v0 + sum) ^ ((v0 >> 5) + k[3]);
    }
    return uvec2(v0, v1);
}

struct NoiseGenerator{
    uint currentNum;
};

float nextFloat(inout NoiseGenerator noiseGenerator) {
    const uint A = 1664525u;
    const uint C = 1013904223u;
    noiseGenerator.currentNum = (A * noiseGenerator.currentNum + C);
    return float(noiseGenerator.currentNum >> 8) * rcp(16777216.0);
}

vec2 nextVec2(inout NoiseGenerator noiseGenerator) {
    vec2 noise;
    noise.x = nextFloat(noiseGenerator);
    noise.y = nextFloat(noiseGenerator);
    return noise;
}

NoiseGenerator initNoiseGenerator(uvec2 texelIndex, uint frameIndex) {
    uint seed = blockCipherTEA(interleave_32bit(texelIndex), frameIndex).x;
    return NoiseGenerator(seed);
}
