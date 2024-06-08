
#include "/lib/surface/BRDF.glsl"

#define PCF_SAMPLES 16 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

const float shadowDistanceRenderMul = 1.0; // [-1.0 1.0]

const int shadowMapResolution = 2048;  // [1024 2048 4096 8192 16384 32768]
const float	shadowDistance	  = 192.0; // [64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0 768.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0]

const float realShadowMapRes = shadowMapResolution * MC_SHADOW_QUALITY;


//================================================================================================//

#include "ShadowDistortion.glsl"

vec3 WorldPosToShadowProjPosBias(in vec3 worldOffsetPos, out float distortFactor) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldOffsetPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	distortFactor = DistortionFactor(shadowClipPos.xy);
	return DistortShadowSpace(shadowClipPos, distortFactor) * 0.5 + 0.5;
}

//================================================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

vec2 BlockerSearch(in vec3 shadowProjPos, in float dither) {
	float searchDepth = 0.0;
	float sumWeight = 0.0;
	float sssDepth = 0.0;

	float searchRadius = 2.0 * shadowProjection[0].x;

	vec2 rot = cossin(dither * TAU) * searchRadius;
	const vec2 angleStep = cossin(TAU * 0.125);
	const mat2 rotStep = mat2(angleStep, -angleStep.y, angleStep.x);
	for (uint i = 0u; i < 8u; ++i, rot *= rotStep) {
		float fi = float(i) + dither;
		vec2 sampleCoord = shadowProjPos.xy + rot * sqrt(fi * 0.125);

		float depthSample = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		float weight = step(depthSample, shadowProjPos.z);

		sssDepth += max0(shadowProjPos.z - depthSample);
		searchDepth += depthSample * weight;
		sumWeight += weight;
	}

	searchDepth *= 1.0 / sumWeight;
	searchDepth = min(2.0 * (shadowProjPos.z - searchDepth) / searchDepth, 0.4);

	return vec2(searchDepth * shadowProjection[0].x, sssDepth * shadowProjectionInverse[2].z);
}

vec3 PercentageCloserFilter(in vec3 shadowProjPos, in float dither, in float penumbraScale) {
	shadowProjPos.z -= 1e-4;

	// const uint steps = 16u;
	const float rSteps = 1.0 / float(PCF_SAMPLES);

	vec3 result = vec3(0.0);

	vec2 rot = cossin(dither * TAU) * penumbraScale;
	const vec2 angleStep = cossin(TAU * 0.125);
	const mat2 rotStep = mat2(angleStep, -angleStep.y, angleStep.x);
	for (uint i = 0u; i < PCF_SAMPLES; ++i, rot *= rotStep) {
		float fi = float(i) + dither;
		vec2 sampleCoord = shadowProjPos.xy + rot * sqrt(fi * rSteps);

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowProjPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = step(shadowProjPos.z, texelFetch(shadowtex0, sampleTexel, 0).x);
		if (sampleDepth0 != sampleDepth1) {
			result += cube(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
		} else 
	#endif
		{ result += sampleDepth1; }
	}

	return result * rSteps;
}

//================================================================================================//

float ScreenSpaceShadow(in vec3 viewPos, in vec3 rayPos, in float dither) {
	vec3 viewlightVector = mat3(gbufferModelView) * worldLightVector;

    vec3 position = ViewToScreenSpace(viewlightVector * -viewPos.z + viewPos);
    vec3 screenDir = normalize(position - rayPos);
    screenDir *= minOf((step(0.0, screenDir) - rayPos) / screenDir);

    rayPos.xy *= viewSize;
    screenDir.xy *= viewSize;

	vec2 absScreenDir = abs(screenDir.xy);
    screenDir *= mix(1.0 / absScreenDir.x, 1.0 / absScreenDir.y, absScreenDir.y > absScreenDir.x);

    vec3 rayStep = screenDir * 3.0;
	rayPos += rayStep * (dither + 1.0);

	float maxThickness = 0.01 * (2.0 - viewPos.z) * gbufferProjectionInverse[1].y;
	float shadow = 1.0;

    for (uint i = 0u; i < 12u; ++i, rayPos += rayStep) {
        if (rayPos.z < 0.0 || rayPos.z - rayStep.z > 1.0) break;
        if (clamp(rayPos.xy, vec2(0.0), viewSize) == rayPos.xy) {
			float sampleDepth = sampleDepth(ivec2(rayPos.xy));

			if (sampleDepth < rayPos.z) {
				float sampleDepthLinear = ScreenToLinearDepth(sampleDepth);
				float traceDepthLinear = ScreenToLinearDepth(rayPos.z);

				if (traceDepthLinear - sampleDepthLinear < maxThickness) {
					shadow = 0.0;
					break;
				}
			}
		}
    }

	return shadow;
}

//================================================================================================//

vec3 CalculateSubsurfaceScattering(in vec3 albedo, in float sssAmount, in float sssDepth, in float LdotV) {
	vec3 coeff = albedo * inversesqrt(GetLuminance(albedo) + 1e-6);
	coeff = oneMinus(0.65 * saturate(coeff)) * (32.0 / sssAmount);

	vec3 subsurfaceScattering =  fastExp(0.375 * coeff * sssDepth) * HenyeyGreensteinPhase(-LdotV, 0.6);
		 subsurfaceScattering += fastExp(0.125 * coeff * sssDepth) * (0.33 * HenyeyGreensteinPhase(-LdotV, 0.35) + 0.17 * rPI);

	//vec3 subsurfaceScattering = fastExp(coeff * sssDepth);
	//subsurfaceScattering *= HenyeyGreensteinPhase(-LdotV, 0.65) + 0.25;
	return subsurfaceScattering * sssAmount * PI;
}

//================================================================================================//

float CalculateFittedBouncedLight(in vec3 normal) {
	vec3 bounceVector = normalize(worldLightVector + vec3(2.0, -6.0, 2.0));
	float bounce = saturate(dot(normal, bounceVector) * 0.5 + 0.5);

	return bounce * (2.0 - bounce) * 3e-2;
}
