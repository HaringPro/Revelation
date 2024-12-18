
#define PCF_SAMPLES 16 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

const float shadowDistanceRenderMul = 1.0; // [-1.0 1.0]
const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

//================================================================================================//

#include "ShadowDistortion.glsl"

vec3 WorldToShadowScreenSpace(in vec3 worldPos, out float distortFactor) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	distortFactor = DistortionFactor(shadowClipPos.xy);
	return DistortShadowSpace(shadowClipPos, distortFactor) * 0.5 + 0.5;
}

//================================================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

float BlockerSearch(in vec3 shadowScreenPos, in float dither) {
	float searchDepth = 0.0;
	float sumWeight = 0.0;

	float searchRadius = 2.0 * shadowProjection[0].x;

	// dither = TentFilter(dither);
	vec2 dir = cossin(dither * TAU) * searchRadius;
	const vec2 angleStep = cossin(TAU * 0.125);
	const mat2 rot = mat2(angleStep, -angleStep.y, angleStep.x);

	for (uint i = 0u; i < 8u; ++i, dir *= rot) {
		float radius = (float(i) + dither) * 0.125;
		vec2 sampleCoord = shadowScreenPos.xy + dir * radius;

		float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		float weight = step(sampleDepth, shadowScreenPos.z);

		searchDepth += sampleDepth * weight;
		sumWeight += weight;
	}

	searchDepth *= 1.0 / sumWeight;
	searchDepth = min(2.0 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.2);

	return searchDepth * shadowProjection[0].x;
}

vec2 BlockerSearchSSS(in vec3 shadowScreenPos, in float dither) {
	float searchDepth = 0.0;
	float sumWeight = 0.0;
	float sssDepth = 0.0;

	float searchRadius = 2.0 * shadowProjection[0].x;

	// dither = TentFilter(dither);
	vec2 dir = cossin(dither * TAU) * searchRadius;
	const vec2 angleStep = cossin(TAU * 0.125);
	const mat2 rot = mat2(angleStep, -angleStep.y, angleStep.x);

	for (uint i = 0u; i < 8u; ++i, dir *= rot) {
		float radius = (float(i) + dither) * 0.125;
		vec2 sampleCoord = shadowScreenPos.xy + dir * radius;

		float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		float weight = step(sampleDepth, shadowScreenPos.z);

		sssDepth += max0(shadowScreenPos.z - sampleDepth);
		searchDepth += sampleDepth * weight;
		sumWeight += weight;
	}

	searchDepth *= 1.0 / sumWeight;
	searchDepth = min(2.0 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.2);

	return vec2(searchDepth * shadowProjection[0].x, sssDepth * shadowProjectionInverse[2].z);
}

vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in float dither, in float penumbraScale) {
	const float rSteps = 1.0 / float(PCF_SAMPLES);

	vec3 result = vec3(0.0);

	vec2 dir = cossin(dither * TAU) * penumbraScale;
	const vec2 angleStep = cossin(TAU * rSteps);
	const mat2 rot = mat2(angleStep, -angleStep.y, angleStep.x);

	for (uint i = 0u; i < PCF_SAMPLES; ++i, dir *= rot) {
		float radius = (float(i) + dither) * rSteps;
		vec2 sampleCoord = shadowScreenPos.xy + dir * radius * inversesqrt(radius);

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, sampleTexel, 0).x);
		if (sampleDepth0 != sampleDepth1) {
			result += pow4(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
		} else 
	#endif
		{ result += sampleDepth1; }
	}

	return result * rSteps;
}

//================================================================================================//

float ScreenSpaceShadow(in vec3 viewPos, in vec3 rayPos, in vec3 viewNormal, in float dither, in float sssAmount) {
	float NdotL = dot(viewLightVector, viewNormal);
	viewPos += length(viewPos) * 3e-4 / maxEps(sqr(NdotL)) * viewNormal;

    vec3 endPos = ViewToScreenSpace(viewLightVector * -viewPos.z + viewPos);
    vec3 rayStep = normalize(endPos - rayPos);
    rayStep *= minOf((step(0.0, rayStep) - rayPos) / rayStep);

    rayPos.xy *= viewSize;
    rayStep.xy *= viewSize;

	const float stepSize = 48.0 / float(SCREEN_SPACE_SHADOWS_SAMPLES);
    rayStep *= stepSize / maxOf(abs(rayStep.xy));

	rayPos += rayStep * (dither + 1.0 - sssAmount);

	float maxThickness = 0.01 * (2.0 - viewPos.z) * gbufferProjectionInverse[1].y;
    float absorption = step(1e-3, sssAmount) * sssAmount;

	float shadow = 1.0;
    for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
        if (rayPos.z < 0.0 || rayPos.z >= 1.0) break;
        if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

		float sampleDepth = loadDepth0(ivec2(rayPos.xy));

		if (sampleDepth < rayPos.z) {
			float sampleDepthLinear = LinearizeDepth(sampleDepth);
			float traceDepthLinear = LinearizeDepth(rayPos.z);

			if (traceDepthLinear - sampleDepthLinear < maxThickness) shadow *= absorption;
		}
 
		if (shadow < 1e-3) break;
   }

	return shadow;
}
