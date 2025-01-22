
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

float BlockerSearch(in vec3 shadowScreenPos, in float dither, in float searchScale) {
	float searchDepth = 0.0;
	float sumWeight = 0.0;

	vec2 searchRadius = searchScale * diagonal2(shadowProjection);

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
	searchDepth = clamp(1.6 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.02, 0.1);

	return searchDepth;
}

vec2 BlockerSearchSSS(in vec3 shadowScreenPos, in float dither, in float searchScale) {
	float searchDepth = 0.0;
	float sumWeight = 0.0;
	float sssDepth = 0.0;

	vec2 searchRadius = searchScale * diagonal2(shadowProjection);

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
	searchDepth = clamp(1.6 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.02, 0.1);

	return vec2(searchDepth, sssDepth * shadowProjectionInverse[2].z);
}

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
	float NdotD = dot(normal, dir);
	float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
	if (k < 0.0) return vec3(0.0);

	return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

#include "/lib/water/WaterWave.glsl"
float CalculateWaterCaustics(in vec3 worldPos, in vec3 lightVector, in float dither) {
	float caustics = 0.0;

	for (uint i = 0u; i < 9u; ++i) {
		vec2 offset = (offset3x3[i] + dither) * 0.125;
		offset = vec2(offset.x - offset.y * 0.5, offset.y * 0.866);

		vec2 waveCoord = worldPos.xz - worldPos.y + offset;
		waveCoord -= lightVector.xz / lightVector.y;
		vec2 waveNormal = CalculateWaterNormal(waveCoord).xy;

		caustics += exp2(-dotSelf(offset - waveNormal) * 3e2);
	}

	return saturate(caustics * 0.7);
}

vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in vec3 worldPos, in float dither, in float penumbraScale) {
	const float rSteps = 1.0 / float(PCF_SAMPLES);

	vec2 penumbraRadius = penumbraScale * diagonal2(shadowProjection);

	vec2 dir = cossin(dither * TAU) * penumbraRadius;
	const vec2 angleStep = cossin(TAU * rSteps);
	const mat2 rot = mat2(angleStep, -angleStep.y, angleStep.x);

	vec3 result = vec3(0.0);
	bool caustics = false;

	for (uint i = 0u; i < PCF_SAMPLES; ++i, dir *= rot) {
		float radius = (float(i) + dither) * rSteps;
		vec2 sampleCoord = shadowScreenPos.xy + dir * radius * inversesqrt(radius);

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, sampleTexel, 0).x);
		if (sampleDepth0 != sampleDepth1) {
			float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
			if (waterMask > 0.1) caustics = true;
			else result += pow4(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
		} else 
	#endif
		{ result += sampleDepth1; }
	}

	result *= rSteps;
	if (caustics) {
		// caustics *= rSteps;
		// float causticAltitude = abs(caustics.x * 512.0 - 128.0 - worldPos.y - eyeAltitude);
		vec3 lightVector = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
		result = vec3(sqr(CalculateWaterCaustics(worldPos + cameraPosition, lightVector, dither)));
	}

	return result;
}

//================================================================================================//

float ScreenSpaceShadow(in vec3 viewPos, in vec3 rayPos, in vec3 viewNormal, in float dither, in float sssAmount) {
	const float stepSize = 48.0 / float(SCREEN_SPACE_SHADOWS_SAMPLES);

	float NdotL = dot(viewLightVector, viewNormal);
	viewPos += length(viewPos) * 3e-4 / maxEps(sqr(NdotL)) * viewNormal;

	float absorption = 0.75 * approxSqrt(sssAmount);

	float shadow = 1.0;

	vec3 endPos = ViewToScreenSpace(viewLightVector * -viewPos.z + viewPos);
	vec3 rayStep = normalize(endPos - rayPos);
	rayStep *= minOf((step(0.0, rayStep) - rayPos) / rayStep);

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;
	rayStep *= stepSize / maxOf(abs(rayStep.xy));

	rayPos += rayStep * (dither + 1.0 - sssAmount);

	float maxThickness = 0.01 * (2.0 - viewPos.z) * gbufferProjectionInverse[1].y;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
		if (rayPos.z < 0.0 || rayPos.z >= 1.0) break;
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

		float sampleDepth = loadDepth0(ivec2(rayPos.xy));

		float difference = ScreenToViewDepth(rayPos.z);
		difference -= ScreenToViewDepth(sampleDepth);

		if (clamp(difference, 0.0, maxThickness) == difference) shadow *= absorption;

		if (shadow < 1e-3) break;
	}

	return shadow;
}

#if defined DISTANT_HORIZONS
float ScreenSpaceShadowDH(in vec3 viewPos, in vec3 rayPos, in vec3 viewNormal, in float dither, in float sssAmount) {
	const float stepSize = 48.0 / float(SCREEN_SPACE_SHADOWS_SAMPLES);

	float NdotL = dot(viewLightVector, viewNormal);
	viewPos += length(viewPos) * 3e-4 / maxEps(sqr(NdotL)) * viewNormal;

	float absorption = 0.75 * approxSqrt(sssAmount);

	float shadow = 1.0;

	vec3 endPos = ViewToScreenSpaceDH(viewLightVector * -viewPos.z + viewPos);
	vec3 rayStep = normalize(endPos - rayPos);
	rayStep *= minOf((step(0.0, rayStep) - rayPos) / rayStep);

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;
	rayStep *= stepSize / maxOf(abs(rayStep.xy));

	rayPos += rayStep * (dither + 1.0 - sssAmount);

	float maxThickness = 0.03 * (2.0 - viewPos.z) * dhProjectionInverse[1].y;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
		if (rayPos.z < 0.0 || rayPos.z >= 1.0) break;
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;

		float sampleDepth = loadDepth0DH(ivec2(rayPos.xy));

		float difference = ScreenToViewDepthDH(rayPos.z);
		difference -= ScreenToViewDepthDH(sampleDepth);

		if (clamp(difference, 0.0, maxThickness) == difference) shadow *= absorption;

		if (shadow < 1e-3) break;
	}

	return shadow;
}
#endif