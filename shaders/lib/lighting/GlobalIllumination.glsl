#ifdef RSM_ENABLED
/* Reflective Shadow Maps */
// Referrence: https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf

#define RSM_SAMPLES 16 // [4 8 12 16 20 24 32 48 64 96 128 256]
#define RSM_RADIUS 10.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 15.0 20.0 25.0 30.0 40.0 50.0 70.0 100.0]
#define RSM_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 40.0 50.0 70.0 100.0]

//================================================================================================//

uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

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

vec3 CalculateRSM(in vec3 viewPos, in vec3 worldNormal, in float dither, in float skyLightmap) {
	const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
	vec3 shadowScreenPos = WorldToShadowScreenPos(worldPos);

	vec3 shadowNormal = mat3(shadowModelView) * worldNormal;
	vec3 projectionInvScale = diagonal3(shadowProjectionInverse);

	const float sqRadius = RSM_RADIUS * RSM_RADIUS;
	const float rSteps = 1.0 / float(RSM_SAMPLES);
	const float falloffScale = 9.0 / RSM_RADIUS;

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 offsetRadius = RSM_RADIUS * diagonal2(shadowProjection);
	vec2 dir = sincos(dither * 32.0 * PI) * offsetRadius;
	dither *= rSteps;

	vec3 sum = vec3(0.0);
	for (uint i = 0u; i < RSM_SAMPLES; ++i, dir *= goldenRotate) {
		float sampleRad 			= float(i) * rSteps + dither;

		vec2 sampleCoord 			= shadowScreenPos.xy + dir * sampleRad;
		ivec2 sampleTexel 			= ivec2(DistortShadowScreenPos(sampleCoord) * realShadowMapRes);

		float sampleDepth 			= texelFetch(shadowtex1, sampleTexel, 0).x * 5.0 - 2.0;

		vec3 sampleVector 			= vec3(sampleCoord, sampleDepth) - shadowScreenPos;
		sampleVector 				= projectionInvScale * sampleVector;

		float sampleSqLen 	 		= dotSelf(sampleVector);
		if (sampleSqLen > sqRadius) continue;

		vec3 sampleDir 				= sampleVector * inversesqrt(sampleSqLen);

		float diffuse 				= dot(shadowNormal, sampleDir);
		if (diffuse < 1e-6) 		continue;

		vec3 sampleColor 			= texelFetch(shadowcolor1, sampleTexel, 0).rgb;

		vec3 sampleNormal 			= decodeUnitVector(sampleColor.xy);

		float bounce 				= dot(sampleNormal, -sampleDir);				
		if (bounce < 1e-6) 			continue;

		float falloff 	 			= rcp((sampleSqLen + 0.2) * falloffScale * inversesqrt(sampleRad));

		float skylightWeight 		= saturate(exp2(-sqr(sampleColor.z - skyLightmap)) * 2.5 - 1.5);

		// vec3 albedo 				= sRGBtoLinear(texelFetch(shadowcolor0, sampleTexel, 0).rgb);
		vec3 albedo 				= pow(texelFetch(shadowcolor0, sampleTexel, 0).rgb, vec3(2.2));

		sum += albedo * falloff * saturate(diffuse * bounce) * skylightWeight;
	}

	sum *= sqRadius * rSteps * RSM_BRIGHTNESS;

	return sum * inversesqrt(maxEps(sum));
}

#else

//================================================================================================//

/* Screen-Space Path Tracing */

#define SSPT_SPP 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define SSPT_BOUNCES 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]

#define SSPT_FALLOFF 0.3 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
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

vec3 sampleRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in vec3 rayPos) {
	if (viewDir.z > -viewPos.z) return vec3(1.5);

	vec3 position = ViewToScreenSpace(viewDir * -viewPos.z + viewPos);
	vec3 screenDir = normalize(position - rayPos);

	float stepLength = minOf((step(0.0, screenDir) - rayPos) / screenDir) * rcp(15.0);

	vec3 rayStep = screenDir * stepLength;
	rayPos += rayStep * dither;

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;

	for (uint i = 0u; i < 15u; ++i, rayPos += rayStep){
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;
		float sampleDepth = readDepth(ivec2(rayPos.xy));

		if (sampleDepth < rayPos.z) {
			float sampleDepthLinear = ScreenToLinearDepth(sampleDepth);
			float traceDepthLinear = ScreenToLinearDepth(rayPos.z);

			if (traceDepthLinear - sampleDepthLinear < 0.2 * traceDepthLinear) return vec3(rayPos.xy, sampleDepth);
		}
	}

	return vec3(1.5);
}

float CalculateBlocklightFalloff(in float blocklight) {
	float fade = rcp(sqr(16.0 - 15.0 * blocklight));
	blocklight += approxSqrt(blocklight) * 0.4 + sqr(blocklight) * 0.6;
	return blocklight * 0.5 * fade;
}

struct TracingData {
	vec3 rayPos;
    vec3 rayDir;
    vec3 viewNormal;
    vec3 worldNormal;
	vec3 brdf;
};

vec3 CalculateSSPT(in vec3 screenPos, in vec3 viewPos, in vec3 worldNormal, in vec2 lightmap, in float dither) {
	lightmap.x = CalculateBlocklightFalloff(lightmap.x) * SSPT_BLENDED_LIGHTMAP;
	lightmap.y *= lightmap.y * lightmap.y * rPI;

    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));

	vec3 sum = vec3(0.0);
	const float f0 = 0.02;

	ivec2 shiftX = ivec2((int(viewWidth) >> 1) + 1, 0);

	#if SSPT_BOUNCES > 1 && !defined SSPT_TEMPORAL_INFINITE_BOUNCES
	// Multiple bounce tracing.

    for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
		// Initialize tracing data.
		TracingData target = TracingData(screenPos, vec3(0.0), viewNormal, worldNormal, vec3(1.0));

		for (uint bounce = 0u; bounce < SSPT_BOUNCES; ++bounce) {
			vec3 sampleDir = sampleCosineVector(target.worldNormal, nextVec2(noiseGenerator));

			target.rayDir = normalize(mat3(gbufferModelView) * sampleDir);

			float NdotL = dot(target.viewNormal, target.rayDir);
			target.rayDir = NdotL < 0.0 ? -target.rayDir : target.rayDir;

			NdotL = dot(target.viewNormal, target.rayDir);

			vec3 targetViewPos = ScreenToViewSpaceRaw(target.rayPos) + target.viewNormal * 1e-2;
			target.rayPos = sampleRaytrace(targetViewPos, target.rayDir, dither, target.rayPos);

			if (target.rayPos.z < 1.0) {
				ivec2 targetTexel = ivec2(target.rayPos.xy);
				vec3 sampleLight = texelFetch(colortex4, (targetTexel >> 1) + shiftX, 0).rgb;

				target.worldNormal = FetchWorldNormal(readGbufferData0(targetTexel));
				target.viewNormal = mat3(gbufferModelView) * target.worldNormal;;

				target.brdf *= readAlbedo(targetTexel);

				target.rayPos.xy *= viewPixelSize;
				vec3 diff = ScreenToViewSpace(target.rayPos) - viewPos;

				float diffSqLen = dotSelf(diff);

				sum += sampleLight * target.brdf * pow(diffSqLen, -SSPT_FALLOFF);
			} else if (lightmap.y + lightmap.x > 1e-3) {
				vec4 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir));
				sum += (skyRadiance.rgb * lightmap.y + lightmap.x) * target.brdf;
				break;
			}
		}
	}

	#else
	// Single bounce tracing.

	for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
			vec3 sampleDir = sampleCosineVector(worldNormal, nextVec2(noiseGenerator));

			vec3 rayDir = normalize(mat3(gbufferModelView) * sampleDir);

			float NdotL = dot(viewNormal, rayDir);
			rayDir = NdotL < 0.0 ? -rayDir : rayDir;

			NdotL = dot(viewNormal, rayDir);

			#if 0
				float brdf = oneMinus(FresnelSchlick(NdotL, f0));
			#else
				const float brdf = 1.0;
			#endif

			vec3 hitPos = sampleRaytrace(viewPos + viewNormal * 1e-2, rayDir, dither, screenPos);

			if (hitPos.z < 1.0) {
				#ifdef SSPT_TEMPORAL_INFINITE_BOUNCES
					vec3 sampleLight = texelFetch(colortex4, ivec2(hitPos.xy) >> 1, 0).rgb * step(0.56, screenPos.z);
				#else
					vec3 sampleLight = texelFetch(colortex4, (ivec2(hitPos.xy) >> 1) + shiftX, 0).rgb;
				#endif

				hitPos.xy *= viewPixelSize;
				vec3 diff = ScreenToViewSpace(hitPos) - viewPos;

				float diffSqLen = dotSelf(diff);

				sum += sampleLight * brdf * pow(diffSqLen, -SSPT_FALLOFF);
			} else if (lightmap.y + lightmap.x > 1e-3) {
				vec4 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir));
				sum += (skyRadiance.rgb * lightmap.y + lightmap.x) * brdf;
			}
		}
	#endif

	return sum * PI * rcp(float(SSPT_SPP));
}
#endif