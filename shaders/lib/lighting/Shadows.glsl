
#define PCF_SAMPLES 16 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

const float shadowDistanceRenderMul = 1.0; // [-1.0 1.0]
const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

//================================================================================================//

#include "ShadowDistortion.glsl"

vec3 WorldToShadowScreenSpace(in vec3 worldPos, out float distortionFactor) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
	return DistortShadowSpace(shadowClipPos, distortionFactor) * 0.5 + 0.5;
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
	searchDepth = clamp(2.0 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.025, 0.25);

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
	searchDepth = clamp(2.0 * (shadowScreenPos.z - searchDepth) / searchDepth, 0.025, 0.25);

	return vec2(searchDepth, sssDepth * shadowProjectionInverse[2].z);
}

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
	float NdotD = dot(normal, dir);
	float k = 1.0 - eta * eta * oms(NdotD * NdotD);
	if (k < 0.0) return vec3(0.0);

	return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

#include "/lib/water/WaterWave.glsl"

#ifdef WATER_CAUSTICS_DISPERSION
vec3 CalculateWaterCaustics(in vec3 worldPos, in vec3[3] lightVector, in float dist, in vec2 dither) {
	vec3 caustics = vec3(0.0);
	worldPos.xz -= worldPos.y;

	vec2[3] waveCoord;
	waveCoord[0] = worldPos.xz + lightVector[0].xz / lightVector[0].y;
	waveCoord[1] = worldPos.xz + lightVector[1].xz / lightVector[1].y;
	waveCoord[2] = worldPos.xz + lightVector[2].xz / lightVector[2].y;

	for (uint i = 0u; i < 9u; ++i) {
		vec2 offset = (offset3x3[i] + dither) * 0.1;

		for (uint j = 0u; j < 3u; ++j) {
			vec2 waveCoord = waveCoord[j] + offset;
			vec2 waveNormal = CalculateWaterNormal(waveCoord).xy;

			caustics[j] += exp2(-sdot(offset - waveNormal * dist) * 512.0);
		}
	}

	return sqr(caustics);
}
#else
float CalculateWaterCaustics(in vec3 worldPos, in vec3 lightVector, in float dist, in vec2 dither) {
	float caustics = 0.0;
	worldPos.xz += lightVector.xz / lightVector.y - worldPos.y;

	for (uint i = 0u; i < 9u; ++i) {
		vec2 offset = (offset3x3[i] + dither) * 0.1;

		vec2 waveCoord = worldPos.xz + offset;
		vec2 waveNormal = CalculateWaterNormal(waveCoord).xy;

		caustics += exp2(-sdot(offset - waveNormal * dist) * 512.0);
	}

	return sqr(caustics);
}
#endif

vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in vec3 worldPos, in float dither, in float penumbraScale) {
	const float rSteps = 1.0 / float(PCF_SAMPLES);

	vec2 penumbraRadius = penumbraScale * diagonal2(shadowProjection);

	vec2 dir = cossin(dither * TAU) * penumbraRadius;
	const vec2 angleStep = cossin(TAU * rSteps);
	const mat2 rot = mat2(angleStep, -angleStep.y, angleStep.x);

	vec3 result = vec3(0.0);
	float causticWeight = 0.0;

	for (uint i = 0u; i < PCF_SAMPLES; ++i, dir *= rot) {
		float radius = (float(i) + dither) * rSteps;
		vec2 sampleCoord = shadowScreenPos.xy + dir * radius * inversesqrt(radius);

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, sampleTexel, 0).x);
		if (sampleDepth0 != sampleDepth1) {
			float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
			if (waterMask > 0.1) causticWeight += sampleDepth1;
			else result += pow4(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
		} else
	#endif
		result += sampleDepth1;
	}

	result *= rSteps;

	#ifdef WATER_CAUSTICS
		if (causticWeight > EPS) {
			causticWeight *= rSteps;
			// float causticAltitude = abs(causticWeight.y * 512.0 - 128.0 - worldPos.y - eyeAltitude);
			worldPos += cameraPosition;

			#ifdef WATER_CAUSTICS_DISPERSION
				vec3[3] lightVector;
				lightVector[0] = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / (WATER_REFRACT_IOR - 0.025));
				lightVector[1] = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
				lightVector[2] = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / (WATER_REFRACT_IOR + 0.025));
				vec3 caustics = CalculateWaterCaustics(worldPos, lightVector, penumbraScale * 8.0, R2(dither) - 0.5);
			#else
				vec3 lightVector = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
				float caustics = CalculateWaterCaustics(worldPos, lightVector, penumbraScale * 8.0, R2(dither) - 0.5);
			#endif
			result += causticWeight * (caustics - result);
		}
	#endif

	return result;
}

//================================================================================================//

float ScreenSpaceShadow(in vec3 viewPos, in vec3 viewNormal, in float dither, in float sssAmount) {
	float viewDist = length(viewPos);
	float NdotL = dot(viewLightVector, viewNormal);
	viewPos += viewDist * maxOf(viewPixelSize) / max(sqr(NdotL), 0.05) * viewNormal;

    float absorption = exp2(-0.25 * approxSqrt(viewDist) / sssAmount);

	vec3 rayDir = viewLightVector * -viewPos.z * (0.1 / float(SCREEN_SPACE_SHADOWS_SAMPLES)) * oms(sssAmount * 0.75);
	rayDir = vec3(diagonal2(gbufferProjection) * rayDir.xy * 0.5, -rayDir.z);

	vec3 rayPos = vec3((diagonal2(gbufferProjection) * viewPos.xy + gbufferProjection[3].xy) * 0.5, -viewPos.z);
	rayPos += dither * rayDir;

	float diffTolerance = 2e-2 + 1e-2 * viewDist;
	float result = 1.0;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayDir) {
		vec2 sampleCoord = rayPos.xy / rayPos.z + taaOffset * 0.5;
		if (any(greaterThan(abs(sampleCoord), vec2(0.5))) || result < 1e-2) break;

		ivec2 sampleTexel = uvToTexel(sampleCoord + 0.5);
		float sampleDepth = loadDepth0(sampleTexel);

		#if defined DISTANT_HORIZONS
			float difference;
			if (sampleDepth > 1.0 - EPS) {
				sampleDepth = loadDepth0DH(sampleTexel);
				difference = ScreenToViewDepthDH(sampleDepth) + rayPos.z;
			} else {
				difference = ScreenToViewDepth(sampleDepth) + rayPos.z;
			}
		#else
			float difference = ScreenToViewDepth(sampleDepth) + rayPos.z;
		#endif

		if (clamp(difference, 0.0, diffTolerance) == difference) result *= absorption;
	}

	return result;
}