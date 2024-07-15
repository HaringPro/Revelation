#if 0
/* Reflective Shadow Maps */
// Referrence: https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf

uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

const int shadowMapResolution = 2048;  // [1024 2048 4096 8192 16384 32768]

//================================================================================================//

#include "ShadowDistortion.glsl"

vec3 WorldToShadowScreenPos(in vec3 worldPos) {
	vec3 shadowPos = transMAD(shadowModelView, worldPos);
	return projMAD(shadowProjection, shadowPos) * 0.5 + 0.5;
}

vec2 DistortShadowScreenPos(in vec2 shadowPos) {
	shadowPos = shadowPos * 2.0 - 1.0;
	shadowPos *= rcp(DistortionFactor(shadowPos));

	return shadowPos * 0.5 + 0.5;
}

//================================================================================================//

vec3 CalculateRSM(in vec3 viewPos, in vec3 worldNormal, in float dither) {
	vec3 total = vec3(0.0);

	const float realShadowMapRes = shadowMapResolution * MC_SHADOW_QUALITY;
	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
	vec3 shadowScreenPos = WorldToShadowScreenPos(worldPos);

	vec3 shadowNormal = mat3(shadowModelView) * worldNormal;

	vec2 scale = RSM_RADIUS * diagonal2(shadowProjection);
	const float sqRadius = RSM_RADIUS * RSM_RADIUS;
	const float rSteps = 1.0 / float(RSM_SAMPLES);
	const float falloffScale = 12.0 / RSM_RADIUS;

	float skyLightmap = texelFetch(colortex7, ivec2(gl_FragCoord.xy * 2.0), 0).g;

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 rot = sincos(dither * 64.0) * scale;
	dither *= rSteps;

	for (uint i = 0u; i < RSM_SAMPLES; ++i, rot *= goldenRotate) {
		float sampleRad 			= float(i) * rSteps + dither;

		vec2 sampleCoord 			= shadowScreenPos.xy + rot * sampleRad;
		ivec2 sampleTexel 			= ivec2(DistortShadowScreenPos(sampleCoord) * realShadowMapRes);

		float sampleDepth 			= texelFetch(shadowtex1, sampleTexel, 0).x * 5.0 - 2.0;

		vec3 sampleVector 			= vec3(sampleCoord, sampleDepth) - shadowScreenPos;
		sampleVector 				= mat3(shadowProjectionInverse) * sampleVector;

		float sampleSqLen 	 		= dotSelf(sampleVector);
		if (sampleSqLen > sqRadius) continue;

		vec3 sampleDir 				= sampleVector * inversesqrt(sampleSqLen);

		float diffuse 				= saturate(dot(shadowNormal, sampleDir));
		if (diffuse < 1e-5) 		continue;

		vec3 sampleColor 			= texelFetch(shadowcolor1, sampleTexel, 0).rgb;

		vec3 sampleNormal 			= DecodeNormal(sampleColor.xy);

		float bounce 				= saturate(dot(sampleNormal, -sampleDir));				
		if (bounce < 1e-5) 			continue;

		float falloff 	 			= rcp((sampleSqLen + 0.5) * falloffScale + sampleRad);

		float skylightWeight 		= saturate(exp2(-sqr(sampleColor.z - skyLightmap)) * 2.5 - 1.5);

		// vec3 albedo 				= sRGBtoLinear(texelFetch(shadowcolor0, sampleTexel, 0).rgb);
		vec3 albedo 				= pow(texelFetch(shadowcolor0, sampleTexel, 0).rgb, vec3(2.2));

		total += albedo * falloff * diffuse * bounce * skylightWeight;
	}

	total *= sqRadius * rSteps;

	return total;
}
#endif

/* Screen-Space Path Tracing */

// #define SSPT_ACCUMULATED_MULTIPLE_BOUNCES

#define SSPT_SPP 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define SSPT_BOUNCES 1 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]

#define SSPT_FALLOFF 0.1 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
#define SSPT_BLENDED_LIGHTMAP 0.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]

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
    return float(noiseGenerator.currentNum >> 8) / 16777216.0;
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

vec3 sampleRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in vec3 rayPos) {
	if (viewDir.z > -viewPos.z) return vec3(1.5);

	vec3 position = ViewToScreenSpace(viewDir * -viewPos.z + viewPos);
	vec3 screenDir = normalize(position - rayPos);

	float stepLength = minOf((step(0.0, screenDir) - rayPos) / screenDir) * rcp(16.0);

	vec3 rayStep = screenDir * stepLength;
	rayPos += rayStep * dither;

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;

	float depthTolerance = max(exp2(2e-2 * viewPos.z - 10.0), rayStep.z * 12.0);

	for (uint i = 0u; i < 16u; ++i, rayPos += rayStep){
		if (clamp(rayPos.xy, vec2(0.0), viewSize) == rayPos.xy) {
			float sampleDepth = sampleDepth(ivec2(rayPos.xy));
			float diff = rayPos.z - sampleDepth;

			if (clamp(diff, 0.0, depthTolerance) == diff) return vec3(rayPos.xy, sampleDepth);
		}
	}

	return vec3(1.5);
}

float CalculateBlocklightFalloff(in float blocklight) {
	float fade = rcp(sqr(16.0 - 15.0 * blocklight));
	blocklight += fastSqrt(blocklight) * 0.4 + sqr(blocklight) * 0.6;
	return blocklight * 0.5 * fade;
}

struct Trace {
    vec3 screenPos;
    vec3 viewDir;
    vec3 viewNormal;
    vec3 worldNormal;
	vec3 brdf;
};

vec3 CalculateSSPT(in vec3 screenPos, in vec3 viewPos, in vec3 worldNormal, in vec2 lightmap, in float dither) {
	lightmap.x = CalculateBlocklightFalloff(lightmap.x) * SSPT_BLENDED_LIGHTMAP;
	#ifdef SSPT_ACCUMULATED_MULTIPLE_BOUNCES
		lightmap.y *= lightmap.y * lightmap.y * rPI;
	#else
		lightmap.y *= lightmap.y * lightmap.y * 0.2;
	#endif
    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;
	vec3 viewDir = normalize(viewPos);

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));

	vec3 total = vec3(0.0);
	const float f0 = 0.04;

	float maxSqLen = sqr(viewPos.z) * 0.2;

	#if SSPT_BOUNCES > 1 && !defined SSPT_ACCUMULATED_MULTIPLE_BOUNCES
    for (uint i = 0u; i < SSPT_SPP; ++i) {
		Trace target = Trace(screenPos, viewDir, viewNormal, worldNormal, vec3(1.0));

		for (uint j = 0u; j < SSPT_BOUNCES; ++j) {
			vec3 sampleDir = sampleCosineVector(target.worldNormal, nextVec2(noiseGenerator));

			target.viewDir = normalize(mat3(gbufferModelView) * sampleDir);

			float NdotL = dot(target.viewNormal, target.viewDir);
			if (dot(target.viewNormal, target.viewDir) < 0.0) target.viewDir = -target.viewDir;

			target.screenPos = sampleRaytrace(viewPos, target.viewDir, dither, target.screenPos);

			float NdotV = maxEps(dot(target.viewNormal, target.viewDir));

			target.brdf *= FresnelSchlick(NdotV, f0);
			// target.brdf *= 0.1;

			if (target.screenPos.z < 1.0) {
				#ifdef SSPT_ACCUMULATED_MULTIPLE_BOUNCES
					vec3 sampleLight = texelFetch(colortex4, ivec2(target.screenPos.xy * 0.5), 0).rgb;
				#else
					vec3 sampleLight = texelFetch(colortex0, ivec2(target.screenPos.xy), 0).rgb;
				#endif

				target.worldNormal = FetchWorldNormal(sampleGbufferData0(ivec2(target.screenPos.xy)));
				target.viewNormal = mat3(gbufferModelView) * target.worldNormal;;

				target.screenPos.xy *= viewPixelSize;
				vec3 diff = ScreenToViewSpace(target.screenPos) - viewPos;

				float diffSqLen = dotSelf(diff);
				if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
					float NdotL = saturate(dot(target.viewNormal, diff * inversesqrt(diffSqLen)));
					target.brdf *= mix(max0(1.0 - NdotL * 2.0 * saturate(1.0 - diffSqLen / maxSqLen)), 1.0, dot(sampleLight, vec3(0.04)));
				}

				total += sampleLight * target.brdf * exp2(-sqrt(diffSqLen) * SSPT_FALLOFF);;
			} else if (lightmap.y + lightmap.x > 1e-3) {
				vec4 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir));
				total += (skyRadiance.rgb * lightmap.y + lightmap.x) * target.brdf;
			}
		}
	}
	#else		
	for (uint i = 0u; i < SSPT_SPP; ++i) {
			vec3 sampleDir = importanceSampleCosine(worldNormal, nextVec2(noiseGenerator));

			vec3 rayDir = normalize(mat3(gbufferModelView) * sampleDir);

			float NdotL = dot(viewNormal, rayDir);
			if (dot(viewNormal, rayDir) < 0.0) rayDir = -rayDir;

			vec3 hitPos = sampleRaytrace(viewPos, rayDir, dither, screenPos);

			float NdotV = maxEps(dot(viewNormal, rayDir));

			float brdf = FresnelSchlick(NdotV, f0);
			// float brdf = 0.1;

			if (hitPos.z < 1.0) {
				#ifdef SSPT_ACCUMULATED_MULTIPLE_BOUNCES
					vec3 sampleLight = texelFetch(colortex4, ivec2(hitPos.xy * 0.5), 0).rgb;
				#else
					vec3 sampleLight = texelFetch(colortex0, ivec2(hitPos.xy), 0).rgb;
				#endif

				hitPos.xy *= viewPixelSize;
				vec3 diff = ScreenToViewSpace(hitPos) - viewPos;

				float diffSqLen = dotSelf(diff);
				if (diffSqLen > 1e-5 && diffSqLen < maxSqLen) {
					float NdotL = saturate(dot(viewNormal, diff * inversesqrt(diffSqLen)));
					brdf *= mix(max0(1.0 - NdotL * 2.0 * saturate(1.0 - diffSqLen / maxSqLen)), 1.0, dot(sampleLight, vec3(0.04)));
				}

				total += sampleLight * brdf * exp2(-sqrt(diffSqLen) * SSPT_FALLOFF);;
			} else if (lightmap.y + lightmap.x > 1e-3) {
				vec4 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir));
				total += (skyRadiance.rgb * lightmap.y + lightmap.x) * brdf;
			}
		}
	#endif

	#ifdef SSPT_ACCUMULATED_MULTIPLE_BOUNCES
		return total * 24.0 * rcp(float(SSPT_SPP));
	#else
		return total * 48.0 * rcp(float(SSPT_SPP));
	#endif
}
