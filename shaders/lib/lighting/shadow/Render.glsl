
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
		vec2 offset = sampleVogelDisk(i, PCSS_SEARCH_SAMPLES, dither);
		vec2 sampleCoord = fma(offset, searchRadius, shadowScreenPos.xy);

		float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		blockerDepth += saturate(shadowScreenPos.z - sampleDepth);
	}

	blockerDepth *= -5.0 / float(PCSS_SEARCH_SAMPLES);
	return blockerDepth * shadowProjectionInverse[2].z;
}

vec3 CalculateWaterCaustics(vec3 worldPos, float waterDepth, float dither) {
    float waterDepthModified = approxSqrt(clamp(waterDepth, 2.0, 64.0));

	vec3 flatRefractDir = refract(vec3(0.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
	vec3 surfacePos = worldPos + flatRefractDir * abs(waterDepthModified / flatRefractDir.y);

	float radius = 0.1 * waterDepthModified;
	float distThresholdInv = -3.0 / radius;

	float caustics = 0.0;
	for (uint i = 0u; i < 16u; ++i) {
		vec3 samplePos = worldPos;
		samplePos.xz += sampleVogelDisk(i, 16, dither) * radius;

		vec2 sampleCoord = WorldToShadowScreenSpace(samplePos).xy;
		vec3 waveNormal = OctDecodeUnorm(texelFetch(shadowcolor1, ivec2(sampleCoord * realShadowMapRes), 0).xy);

		vec3 refractDir = refract(vec3(0.0, -1.0, 0.0), waveNormal, 1.0 / WATER_IOR);
		vec3 refractedPos = samplePos + refractDir * abs(waterDepthModified / refractDir.y);

		caustics += saturate(fma(distance(surfacePos, refractedPos), distThresholdInv, 1.0));
	}

	return sqr(caustics) * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}

vec3 PercentageCloserFilter(vec3 shadowScreenPos, vec3 worldPos, float dither, float blockerDepth, float distortionFactor) {
	blockerDepth *= mix(sunAngularRadius, moonAngularRadius, step(0.5, sunAngle)) * 2.0;

	const float minRadius = 0.015;
	float sharpenFactor = saturate(blockerDepth * rcp(minRadius));

	blockerDepth = clamp(blockerDepth, minRadius, 0.25);
	vec2 penumbraRadius = blockerDepth * distortionFactor * diagonal2(shadowProjection);

	float shadow = 0.0;
	vec3 color = vec3(0.0);
	vec2 waterData = vec2(0.0); // (depth, count)

	for (uint i = 0u; i < PCSS_FILTER_SAMPLES; ++i) {
		vec2 offset = sampleVogelDisk(i, PCSS_FILTER_SAMPLES, dither);
		vec2 sampleCoord = fma(offset, penumbraRadius, shadowScreenPos.xy);

		float sampleDepth1 = texture(shadowtex1, vec3(sampleCoord, shadowScreenPos.z)).x;
		shadow += sampleDepth1;

	#ifdef COLORED_SHADOWS
		if (floatBitsToUint(sampleDepth1) > 0u) {
			ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
			float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;

            if (shadowScreenPos.z > sampleDepth0) {
                float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
                if (waterMask > 0.5) {
                    waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
                } else {
                    color += cube(texelFetch(shadowcolor0, sampleTexel, 0).rgb);
                }
            } else {
                color += 1.0;
            }
        }
	#endif
	}

	// Early out if shadowed
	if (shadow < EPS) return vec3(0.0);

	const float rSteps = 1.0 / float(PCSS_FILTER_SAMPLES);
	shadow *= rSteps;
	color *= rSteps;

	#ifndef COLORED_SHADOWS
		color = vec3(1.0);
	#endif

	#ifdef WATER_CAUSTICS
		if (waterData.y > EPS) {
			waterData.x /= waterData.y;

			float waterDepth = waterData.x * shadowProjectionInverse[2].z * 5.0;
			vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
			color = mix(color, caustics, waterData.y * rSteps);
		}
	#endif

	// Sharpen the near shadow
	shadow = mix(smoothstep(0.3, 0.7, shadow), shadow, sharpenFactor);
	return shadow * color;
}

vec3 CalculatePCSS(vec3 worldPos, vec3 normalOffset, float dither, out float blockerDepth) {
	blockerDepth = 0.0;

	float distortionFactor;
	vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortionFactor);
	shadowScreenPos.z -= 3e-8 * (1.0 + dither) * shadowProjectionInverse[1].y * distortionFactor;

	vec3 result = vec3(1.0);
	if (saturate(shadowScreenPos) == shadowScreenPos) {
		blockerDepth = BlockerSearch(shadowScreenPos, dither * TAU, 0.15 * distortionFactor);

		result = PercentageCloserFilter(shadowScreenPos, worldPos, dither * TAU, blockerDepth, distortionFactor);
	}

	return result;
}

//================================================================================================//

float ScreenSpaceShadow(vec3 rayPos, vec3 viewPos, float dither, float sssAmount) {
	vec3 rayDir = ViewToScreenPos(shadowDirView * abs(viewPos.z) + viewPos) - rayPos;
	rayDir *= minOf((step(0.0, rayDir) - rayPos) / rayDir);
	rayDir *= inversesqrt(sdot(rayDir.xy));

	vec3 rayStep = rayDir * (0.05 / float(SCREEN_SPACE_SHADOWS_SAMPLES));
	rayPos += dither * rayStep;

	float viewDistInv = inversesqrt(sdot(viewPos));
	float diffTolerance = 5e-4 * viewDistInv;
	float absorption = exp2(-0.125 / (viewDistInv * sssAmount));

	float result = 1.0;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
		if (saturate(rayPos.xy) != rayPos.xy || result < 1e-2) break;

		ivec2 sampleTexel = uvToTexelScaled(rayPos.xy);
		float sampleDepth = loadDepth0(sampleTexel);

        #if defined PARALLAX && defined PARALLAX_SHADOW
            float sampleParallaxOffset = loadParallaxOffset(sampleTexel);
            sampleDepth += sampleParallaxOffset;
        #endif

		bool hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;

		#if defined LOD_MOD
			if (sampleDepth > 1.0 - EPS) {
				sampleDepth = loadDepth0Lod(sampleTexel);
				sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(sampleDepth));
                #if defined PARALLAX && defined PARALLAX_SHADOW
                    sampleDepth += sampleParallaxOffset;
                #endif
				hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
			} else
		#endif
		if (hit) {
			vec2 samplePos = rayPos.xy * originViewSize + 0.5;
			samplePos *= RENDER_SCALE;
			vec2 samplePosFloor = floor(samplePos);
			vec2 samplePosFract = samplePos - samplePosFloor;

			vec4 sh = textureGather(depthtex0, samplePosFloor * originTexelSize);
			vec2 temp = mix(sh.wx, sh.zy, vec2(samplePosFract.x));
			sampleDepth = mix(temp.x, temp.y, samplePosFract.y);
            #if defined PARALLAX && defined PARALLAX_SHADOW
                sampleDepth += sampleParallaxOffset;
            #endif

			hit = abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance;
		}

		result *= saturate(absorption + float(!hit));
	}

	return result;
}
