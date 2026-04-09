
#define PCSS_SEARCH_SAMPLES 8 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]
#define PCSS_FILTER_SAMPLES 16 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]

//================================================================================================//

#include "Common.glsl"

vec3 WorldToShadowScreenSpace(vec3 worldPos) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	return DistortShadowSpace(shadowClipPos) * 0.5 + 0.5;
}

vec3 WorldToShadowScreenSpace(vec3 worldPos, out float distortionFactor) {
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

float BlockerSearch(vec3 shadowScreenPos, float dither, float searchScale) {
	float blockerDepth = 0.0;

	vec2 searchRadius = searchScale * diagonal2(shadowProjection);

	for (uint i = 0u; i < PCSS_SEARCH_SAMPLES; ++i) {
		vec2 sampleCoord = shadowScreenPos.xy + sampleVogelDisk(i, PCSS_SEARCH_SAMPLES, dither) * searchRadius;

		float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		blockerDepth += saturate(shadowScreenPos.z - sampleDepth);
	}

	blockerDepth *= -5.0 / float(PCSS_SEARCH_SAMPLES);
	return blockerDepth * shadowProjectionInverse[2].z;
}

vec3 CalculateWaterCaustics(vec3 worldPos, float waterDepth, float dither) {
	vec3 surfacePos = worldPos - vec3(0.0, 1.0, 0.0);

	float caustics = 0.0;
	for (uint i = 0u; i < 16u; ++i) {
		vec3 samplePos = worldPos;
		samplePos.xz += sampleVogelDisk(i, 16, dither) * 0.15;

		vec2 sampleCoord = WorldToShadowScreenSpace(samplePos).xy;
		vec3 waveNormal = OctDecodeUnorm(texture(shadowcolor1, sampleCoord).xy);

		vec3 refractDir = refract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_IOR);
		vec3 refractedPos = samplePos + refractDir * abs(1.0 / refractDir.y);

		caustics += saturate(1.0 - 20.0 * distance(surfacePos, refractedPos));
	}

	return -smin(-caustics, -0.1, 0.15) * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}

vec3 PercentageCloserFilter(vec3 shadowScreenPos, vec3 worldPos, float dither, float blockerDepth) {
	const float rSteps = 1.0 / float(PCSS_FILTER_SAMPLES);

	vec2 penumbraRadius = min(sunAngularRadius * 2.0 * blockerDepth, 0.25) * diagonal2(shadowProjection);

	vec3 result = vec3(0.0);
	vec2 waterData = vec2(0.0);
    // float sssDepth = 0.0;

	for (uint i = 0u; i < PCSS_FILTER_SAMPLES; ++i) {
		vec2 offset = sampleVogelDisk(i, PCSS_FILTER_SAMPLES, dither) * penumbraRadius;
		vec2 sampleCoord = shadowScreenPos.xy + offset;

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;
        // sssDepth += saturate(shadowScreenPos.z - sampleDepth0);

		if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
			float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
			if (waterMask > EPS) {
				waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
			} else {
				result += cube(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
			}
		} else
	#endif
		result += sampleDepth1;
	}

	result *= rSteps;
	// sssDepth *= rSteps;

	#ifdef WATER_CAUSTICS
		if (waterData.y > EPS) {
			waterData.x /= waterData.y;

			float waterDepth = waterData.x * shadowProjectionInverse[2].z * 5.0;
			vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
			result = mix(result, caustics, waterData.y * rSteps);
		}
	#endif

	// result += exp2(32.0 * shadowProjectionInverse[2].z * sssDepth) * sssAmount;

	return result;
}

vec3 CalculatePCSS(vec3 worldPos, vec3 normalOffset, float dither, out float blockerDepth) {
	blockerDepth = 0.0;

	float distortionFactor;
	vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortionFactor);
	shadowScreenPos.z -= 3e-8 * (1.0 + dither) * shadowProjectionInverse[1].y * distortionFactor;

	vec3 pcss = vec3(1.0);
	if (saturate(shadowScreenPos) == shadowScreenPos) {
		blockerDepth = BlockerSearch(shadowScreenPos, dither * TAU, 0.15 * distortionFactor);

		const float minRadius = 0.008 / sunAngularRadius;
		float sharpenFactor = saturate(blockerDepth * rcp(minRadius));

		pcss = PercentageCloserFilter(shadowScreenPos, worldPos, dither * TAU, max(blockerDepth, minRadius) * distortionFactor);
		pcss = mix(smoothstep(0.3, 0.7, pcss), pcss, sharpenFactor); // Sharpen the edges of the shadow
	}

	return pcss;
}

//================================================================================================//

float ScreenSpaceShadow(vec3 rayPos, vec3 viewPos, float dither, float sssAmount) {
	vec3 rayDir = ViewToScreenPos(viewLightDir * abs(viewPos.z) + viewPos) - rayPos;
	rayDir *= minOf((step(0.0, rayDir) - rayPos) / rayDir);
	rayDir *= inversesqrt(sdot(rayDir.xy));

	vec3 rayStep = rayDir * (0.05 / float(SCREEN_SPACE_SHADOWS_SAMPLES));
	rayPos += (dither + 0.5) * rayStep;

	float viewDistInv = inversesqrt(sdot(viewPos));
	float diffTolerance = 5e-4 * viewDistInv;
    float absorption = exp2(-0.125 / (viewDistInv * sssAmount));

	float result = 1.0;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
		if (saturate(rayPos.xy) != rayPos.xy || result < 1e-2) break;

		ivec2 sampleTexel = uvToTexel(rayPos.xy);
		float sampleDepth = loadDepth0(sampleTexel);
		bool hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;

		#if defined LOD_MOD
			if (sampleDepth > 1.0 - EPS) {
				sampleDepth = loadDepth0Lod(sampleTexel);
				sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(sampleDepth));
				hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
			} else
		#endif
		if (hit) {
			vec2 samplePos = rayPos.xy * viewSize + 0.5;
			vec2 samplePosFloor = floor(samplePos);
			vec2 samplePosFract = samplePos - samplePosFloor;

			vec4 sh = textureGather(depthtex0, samplePosFloor * viewPixelSize);
			vec2 temp = mix(sh.wx, sh.zy, vec2(samplePosFract.x));
			sampleDepth = mix(temp.x, temp.y, samplePosFract.y);

			hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
		}

		result *= saturate(absorption + 1.0 - float(hit));
	}

	return result;
}