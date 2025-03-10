#ifdef RSM_ENABLED
/* Reflective Shadow Maps */
// Reference: https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf

#define RSM_SAMPLES 16 // [4 8 12 16 20 24 32 48 64 96 128 256]
#define RSM_RADIUS 10.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 15.0 20.0 25.0 30.0 40.0 50.0 70.0 100.0]
#define RSM_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 40.0 50.0 70.0 100.0]

//================================================================================================//

uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

#include "ShadowDistortion.glsl"

//================================================================================================//

vec3 CalculateRSM(in vec3 viewPos, in vec3 worldNormal, in float dither, in float skyLightmap) {
	const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

	vec3 shadowNormal = mat3(shadowModelView) * worldNormal;
	vec3 projectionScale = diagonal3(shadowProjection);
	vec3 projectionInvScale = diagonal3(shadowProjectionInverse);

	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
	vec3 shadowPos = transMAD(shadowModelView, worldPos);
	vec3 shadowClipPos = projectionScale * shadowPos + shadowProjection[3].xyz;

	const float sqRadius = RSM_RADIUS * RSM_RADIUS;
	const float rSteps = 1.0 / float(RSM_SAMPLES);

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 offsetRadius = RSM_RADIUS * projectionScale.xy;
	vec2 dir = sincos(dither * 16.0 * PI) * offsetRadius;
	dither *= rSteps;

	vec3 sum = vec3(0.0);
	for (uint i = 0u; i < RSM_SAMPLES; ++i, dir *= goldenRotate) {
		float sampleRad 			= float(i) * rSteps + dither;

		vec2 sampleClipCoord 		= shadowClipPos.xy + dir * sampleRad;
		vec2 sampleScreenCoord		= sampleClipCoord * rcp(DistortionFactor(sampleClipCoord)) * 0.5 + 0.5;
		ivec2 sampleTexel 			= ivec2(sampleScreenCoord * realShadowMapRes);

		float sampleDepth 			= texelFetch(shadowtex1, sampleTexel, 0).x * 10.0 - 5.0;

		vec3 sampleVector 			= vec3(sampleClipCoord, sampleDepth) - shadowClipPos;
		sampleVector 				= projectionInvScale * sampleVector;

		float sampleSqLen 	 		= sdot(sampleVector);
		if (sampleSqLen > sqRadius) continue;

		vec3 sampleDir 				= sampleVector * inversesqrt(sampleSqLen);

		float diffuse 				= dot(shadowNormal, sampleDir);
		if (diffuse < 1e-6) 		continue;

		vec3 sampleColor 			= texelFetch(shadowcolor1, sampleTexel, 0).rgb;

		vec3 sampleNormal 			= decodeUnitVector(sampleColor.xy);

		float bounce 				= dot(sampleNormal, -sampleDir);				
		if (bounce < 1e-6) 			continue;

		float falloff 	 			= sampleRad / (sampleSqLen + RSM_RADIUS * rSteps * 0.25);

		float skylightWeight 		= saturate(1.0 - sqr(sampleColor.z - skyLightmap) * 2.0);

		vec3 albedo 				= sRGBtoLinearApprox(texelFetch(shadowcolor0, sampleTexel, 0).rgb);

		sum += albedo * falloff * saturate(diffuse * bounce) * skylightWeight;
	}

	sum *= sqRadius * rSteps * RSM_BRIGHTNESS * 0.5;

	return saturate(sum);
}

#else

//================================================================================================//

/* Screen-Space Path Tracing */

#define SSPT_SPP 2 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define INF 1
#define SSPT_BOUNCES INF // [INF]

#define SSPT_RR_MIN_BOUNCES 1 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 22 24]
#define SSPT_BLENDED_LIGHTMAP 0.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]

vec3 sampleRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in vec3 rayPos) {
	if (viewDir.z > max0(-viewPos.z)) return vec3(1e6);

	vec3 endPos = ViewToScreenSpace(viewDir + viewPos);
	vec3 rayDir = normalize(endPos - rayPos);

	float stepLength = minOf((step(0.0, rayDir) - rayPos) / rayDir) * rcp(16.0);

	vec3 rayStep = rayDir * stepLength;
	rayPos += rayStep * dither;

	rayPos.xy *= viewSize;
	rayStep.xy *= viewSize;

	for (uint i = 0u; i < 16u; ++i, rayPos += rayStep) {
		if (clamp(rayPos.xy, vec2(0.0), viewSize) != rayPos.xy) break;
		float sampleDepth = loadDepth0(ivec2(rayPos.xy));

		if (sampleDepth < rayPos.z) {
			float sampleDepthLinear = ScreenToViewDepth(sampleDepth);
			float traceDepthLinear = ScreenToViewDepth(rayPos.z);
			#if defined DISTANT_HORIZONS
				if (sampleDepth > 0.999999) sampleDepthLinear = ScreenToViewDepthDH(loadDepth0DH(ivec2(rayPos.xy)));
			#endif

			if (traceDepthLinear - sampleDepthLinear < 0.2 * traceDepthLinear) return vec3(rayPos.xy, sampleDepth);
		}
	}

	return vec3(1e6);
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
	vec3 contribution;
};

vec3 CalculateSSPT(in vec3 screenPos, in vec3 viewPos, in vec3 worldNormal, in vec2 lightmap) {
	lightmap.x = CalculateBlocklightFalloff(lightmap.x) * SSPT_BLENDED_LIGHTMAP;
	lightmap.y *= lightmap.y * lightmap.y;

	mat3 gbufferModelView = mat3(gbufferModelView);
    vec3 viewNormal = gbufferModelView * worldNormal;

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));

    #if defined DISTANT_HORIZONS
        float screenDepthMax = ViewToScreenDepth(ScreenToViewDepthDH(1.0));
    #else
        #define screenDepthMax 1.0
    #endif

	vec3 sum = vec3(0.0);

	#if SSPT_BOUNCES > 1
	// Multiple bounce tracing.

    for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
		// Initialize tracing data.
		TracingData target = TracingData(screenPos, vec3(0.0), viewNormal, worldNormal, vec3(1.0));

		for (uint bounce = 1u; bounce <= SSPT_BOUNCES; ++bounce) {
			vec3 sampleDir = sampleCosineVector(target.worldNormal, nextVec2(noiseGenerator));

			// target.rayDir = dot(target.worldNormal, target.rayDir) < 0.0 ? -target.rayDir : target.rayDir;
			target.rayDir = normalize(gbufferModelView * sampleDir);

			float dither = nextFloat(noiseGenerator);
			vec3 targetViewPos = ScreenToViewSpaceRaw(target.rayPos) + target.viewNormal * 1e-2;
			target.rayPos = sampleRaytrace(targetViewPos, target.rayDir, dither, target.rayPos);

			if (target.rayPos.z < screenDepthMax) {
				ivec2 targetTexel = ivec2(target.rayPos.xy);
				vec3 sampleRadiance = texelFetch(colortex4, targetTexel >> 1, 0).rgb;

				target.worldNormal = FetchWorldNormal(loadGbufferData0(targetTexel));
				target.viewNormal = gbufferModelView * target.worldNormal;;

				sum += sampleRadiance * target.contribution;

				target.contribution *= loadAlbedo(targetTexel);
				target.rayPos.xy *= viewPixelSize;
			} else if (dot(lightmap, vec2(1.0)) > 1e-3) {
				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir) + vec2(0.0, 0.5)).rgb;
				sum += (skyRadiance * lightmap.y + lightmap.x) * target.contribution;
				break;
			}

            // Russian roulette
			if (bounce >= SSPT_RR_MIN_BOUNCES) {
				float probability = saturate(luminance(target.contribution));
				if (probability < dither) break;
				target.contribution *= rcp(probability);
			}
		}
	}

	#else
	// Single bounce tracing.

	for (uint spp = 0u; spp < SSPT_SPP; ++spp) {
			vec3 sampleDir = sampleCosineVector(worldNormal, nextVec2(noiseGenerator));

			vec3 rayDir = normalize(gbufferModelView * sampleDir);
			// rayDir = dot(viewNormal, rayDir) < 0.0 ? -rayDir : rayDir;

			vec3 hitPos = sampleRaytrace(viewPos + viewNormal * 1e-2, rayDir, nextFloat(noiseGenerator), screenPos);

			if (hitPos.z < screenDepthMax) {
				vec3 sampleRadiance = texelFetch(colortex4, ivec2(hitPos.xy * 0.5), 0).rgb;

				sum += sampleRadiance;
			} else if (dot(lightmap, vec2(1.0)) > 1e-3) {
				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(sampleDir) + vec2(0.0, 0.5)).rgb;
				sum += skyRadiance * lightmap.y + lightmap.x;
			}
		}
	#endif

	return sum * rcp(float(SSPT_SPP));
}
#endif