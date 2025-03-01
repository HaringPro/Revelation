#version 450 core

/*
--------------------------------------------------------------------------------

	Revoxelation Shaders

	Copyright (C) 2024 HaringPro
	All Rights Reserved

	Pass: Deferred lighting and sky rendering
		  Compute specular reflections

--------------------------------------------------------------------------------
*/

#define PASS_DEFERRED_LIGHTING
#define RANDOM_NOISE

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,1,15 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out vec4 specularCurrent;
layout (location = 2) out vec4 specularHistory;

//======// Input //===============================================================================//

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

// flat in mat4x3 skySH;

//======// Uniform //=============================================================================//

#if defined CLOUDS && !defined CLOUD_CBR_ENABLED
	uniform sampler3D COMBINED_TEXTURE_SAMPLER; // Combined atmospheric LUT
#endif

uniform sampler2D colortex15; // Specular accumulation history

#include "/lib/universal/Uniform.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Offset.glsl"
#include "/lib/universal/Noise.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/Celestial.glsl"

#ifdef AURORA
	#include "/lib/atmosphere/Aurora.glsl"
#endif

#if defined CLOUDS && !defined CLOUD_CBR_ENABLED
	#include "/lib/atmosphere/PrecomputedAtmosphericScattering.glsl"
	#include "/lib/atmosphere/clouds/Render.glsl"
#endif
#ifdef CLOUD_SHADOWS
	#include "/lib/atmosphere/clouds/Shadows.glsl"
#endif

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

// #if AO_ENABLED > 0
// 	#include "/lib/lighting/AmbientOcclusion.glsl"
// #endif

// #include "/lib/SpatialUpscale.glsl"

#include "/lib/surface/Reflection.glsl"

// Reference: https://www.researchgate.net/publication/354065087_ReBLUR_A_Hierarchical_Recurrent_Denoiser

float SpecularMagicCurve(float roughness, float power) {
    float f = 1.0 - exp2(-200.0 * roughness * roughness);
    return f * pow(roughness, power);
}

void SpecularAccumulation(in vec2 prevCoord, in float linearDepth, in vec3 worldNormal, in float roughness) {
    if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
        vec4 prevSpecular = vec4(0.0);
        float sumWeight = 0.0;

        prevCoord += (prevTaaOffset - taaOffset) * 0.125;

        // Custom bilinear filter
        vec2 prevTexel = prevCoord * viewSize - vec2(0.5);
        ivec2 floorTexel = ivec2(floor(prevTexel));
        vec2 fractTexel = prevTexel - vec2(floorTexel);

        float bilinearWeight[4] = {
            oms(fractTexel.x) * oms(fractTexel.y),
            fractTexel.x           * oms(fractTexel.y),
            oms(fractTexel.x) * fractTexel.y,
            fractTexel.x           * fractTexel.y
        };

        ivec2 texelEnd = ivec2(viewSize) - 1;

        for (uint i = 0u; i < 4u; ++i) {
            ivec2 sampleTexel = floorTexel + offset2x2[i];
            if (clamp(sampleTexel, ivec2(0), texelEnd) == sampleTexel) {
			    vec2 sampleData = texelFetch(colortex14, sampleTexel, 0).zw;
                #define prevLinerDepth sampleData.y

                if (abs((linearDepth - prevLinerDepth) - cameraMovement.z) < 0.1 * abs(linearDepth)) {
                    vec3 prevWorldNormal = FetchWorldNormal(sampleData.x);
                    float weight = bilinearWeight[i] * saturate(dot(prevWorldNormal, worldNormal) * 16.0 - 15.0);

                    prevSpecular += texelFetch(colortex15, sampleTexel, 0) * weight;
                    sumWeight += weight;
                }
            }
        }

        if (sumWeight > 1e-6) {
            prevSpecular *= 1.0 / sumWeight;

            float frameIndex = min(prevSpecular.a, SpecularMagicCurve(roughness, 0.25) * PT_SPECULAR_MAX_ACCUM_FRAMES) + 1.0;
			// frameIndex *= exp2(-cameraVelocity * (0.25 / frameTime)) * 0.75 + 0.25;
            float alpha = rcp(frameIndex);

            specularCurrent.rgb = specularHistory.rgb = mix(prevSpecular.rgb, specularCurrent.rgb, alpha);
			specularHistory.a = frameIndex;
		}
    }
}

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	float depth = loadDepth0(screenTexel);

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	uvec4 gbufferData0 = loadGbufferData0(screenTexel);

	uint materialID = gbufferData0.y;

	vec3 albedoRaw = loadAlbedo(screenTexel);
	vec3 albedo = sRGBtoLinear(albedoRaw);

	if (depth > 0.999999 + materialID) {
		vec2 skyViewCoord = FromSkyViewLutParams(worldDir);
		vec3 skyRadiance = textureBicubic(colortex5, skyViewCoord).rgb;

		vec3 celestial = RenderSun(worldDir, worldSunVector);
		vec3 moonDisc = mix(albedo, GetLuminance(albedo) * vec3(0.7, 1.1, 1.5), 0.5) * 0.1;
		#ifdef GALAXY
			celestial += mix(RenderGalaxy(worldDir), moonDisc, bvec3(albedo.g > 0.06)); // Use bvec3 to avoid errors with some drivers
		#else
			celestial += mix(RenderStars(worldDir), moonDisc, bvec3(albedo.g > 0.06)); // Use bvec3 to avoid errors with some drivers
		#endif

		vec3 transmittance = texture(colortex10, skyViewCoord).rgb;
		sceneOut = skyRadiance + transmittance * celestial;

		#ifdef CLOUDS
			#ifndef CLOUD_CBR_ENABLED
				float dither = Bayer64Temporal(gl_FragCoord.xy);
				vec4 cloudData = RenderClouds(worldDir/* , skyRadiance */, dither);
			#else
				vec4 cloudData = textureBicubic(colortex9, screenCoord);
			#endif
			sceneOut = sceneOut * cloudData.a + cloudData.rgb;
		#endif
	} else {
		sceneOut = vec3(0.0);
		worldPos += gbufferModelViewInverse[3].xyz;

		vec2 lightmap = Unpack2x8U(gbufferData0.x);
		lightmap.y = saturate(lightmap.y + float(isEyeInWater));
		vec3 flatNormal = FetchFlatNormal(gbufferData0);
		#ifdef NORMAL_MAPPING
			vec3 worldNormal = FetchWorldNormal(gbufferData0);
		#else
			vec3 worldNormal = flatNormal;
		#endif
		vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

		#ifdef SPECULAR_MAPPING
			vec4 gbufferData1 = loadGbufferData1(screenTexel);
			vec4 specularTex = vec4(Unpack2x8(gbufferData1.x), Unpack2x8(gbufferData1.y));
			Material material = GetMaterialData(specularTex);
		#else
			Material material = Material(materialID == 46u || materialID == 47u ? 0.005 : 1.0, 0.0, DEFAULT_DIELECTRIC_F0, 0.0, false, false);
		#endif

		float sssAmount = 0.0;
		#if SUBSURFACE_SCATTERING_MODE < 2
			// Hard-coded sss amount for certain materials
			switch (materialID) {
				case 9u: case 10u: case 11u: case 12u: case 27u: case 28u: // Plants
					sssAmount = 0.5;
					break;
				case 13u: // Leaves
					sssAmount = 0.9;
					break;
				// case 37u: case 39u: // Weak SSS
				// 	sssAmount = 0.5;
				// 	break;
				// case 38u: case 47u: // Strong SSS
				// 	sssAmount = 0.8;
				// 	break;
				case 40u: // Particles
					sssAmount = 0.35;
					break;
			}
		#endif
		#if TEXTURE_FORMAT == 0 && SUBSURFACE_SCATTERING_MODE > 0 && defined SPECULAR_MAPPING
			sssAmount = max(sssAmount, specularTex.b * step(64.5 * r255, specularTex.b));
		#endif

		// Remap sss amount to [0, 1] range
		sssAmount = remap(64.0 * r255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		float dither = BlueNoiseTemporal(screenTexel);

		const float ao = 1.0;

		float worldDistSquared = sdot(worldPos);
		vec3 normalOffset = flatNormal * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));

		#if RENDER_MODE == 1
		#ifdef DEBUG_VARIANCE
			sceneOut = vec3(texelFetch(colortex3, screenTexel, 0).a);
			return;
		#endif

		// Cloud shadows
		#ifdef CLOUD_SHADOWS
			// float cloudShadow = CalculateCloudShadows(worldPos);
			vec2 cloudShadowCoord = WorldToCloudShadowCoord(worldPos);
			float cloudShadow = textureBicubic(colortex10, saturate(cloudShadowCoord)).a;
			cloudShadow = min(cloudShadow, 1.0 - wetness * 0.6);
		#else
			float cloudShadow = 1.0 - wetness * 0.96;
		#endif

		// Sunlight
		vec3 sunlightMult = cloudShadow * directIlluminance;
		vec3 specularHighlight = vec3(0.0);

		// float worldDistSquared = sdot(worldPos);
		float distanceFade = sqr(pow16(0.64 * rcp(shadowDistance * shadowDistance) * sdot(worldPos.xz)));

		bool doShadows = NdotL > 1e-3;
		bool doSss = sssAmount > 1e-3;
		bool inShadowMapRange = distanceFade < 1e-6;

		// Shadows and SSS
        if (doShadows || doSss) {
			vec3 shadow = sunlightMult;

			// Apply shadowmap
        	if (inShadowMapRange) {
				float distortFactor;
				// vec3 normalOffset = flatNormal * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
				vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortFactor);	

				if (saturate(shadowScreenPos) == shadowScreenPos) {
					vec2 blockerSearch;
					// Sub-surface scattering
					if (doSss) {
						blockerSearch = BlockerSearchSSS(shadowScreenPos, dither, 0.25 * (1.0 + sssAmount) / distortFactor);
						vec3 subsurfaceScattering = CalculateSubsurfaceScattering(albedo, sssAmount, blockerSearch.y, LdotV);

						// Formula from https://www.alanzucconi.com/2017/08/30/fast-subsurface-scattering-1/
						// float bssrdf = sqr(saturate(dot(worldDir, worldLightVector + 0.2 * worldNormal))) * 4.0;
						sceneOut += subsurfaceScattering * sunlightMult * ao * oms(NdotL);
					} else {
						blockerSearch.x = BlockerSearch(shadowScreenPos, dither, 0.25 / distortFactor);
					}

					// Shadows
					if (doShadows) {
						shadowScreenPos.z -= (worldDistSquared * 1e-9 + 3e-6) * (1.0 + dither) * distortFactor * shadowDistance;

						shadow *= PercentageCloserFilter(shadowScreenPos, worldPos, dither, 0.5 * blockerSearch.x / distortFactor) * saturate(lightmap.y * 1e8);
					}
				}
			}

			// Process diffuse and specular highlights
			if (doShadows && dot(shadow, vec3(1.0)) > 1e-6 || doSss && !inShadowMapRange) {
				#ifdef SCREEN_SPACE_SHADOWS
					#if defined NORMAL_MAPPING
						vec3 viewFlatNormal = mat3(gbufferModelView) * flatNormal;
					#else
						#define viewFlatNormal viewNormal
					#endif

					shadow *= materialID == 39u ? 1.0 : ScreenSpaceShadow(viewPos, screenPos, viewFlatNormal, dither, sssAmount);
				#endif

				// Apply parallax shadows
				#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
					#if !defined SPECULAR_MAPPING
						vec4 gbufferData1 = loadGbufferData1(screenTexel);
					#endif
					shadow *= oms(gbufferData1.z);
				#endif

				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotV = abs(dot(worldNormal, -worldDir));
				float NdotH = saturate((NdotL + NdotV) * halfwayNorm);
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				// Sunlight diffuse
				vec3 sunlightDiffuse = DiffuseHammon(LdotV, NdotV, NdotL, NdotH, material.roughness, albedo);
				sunlightDiffuse += sssAmount * (SUBSURFACE_SCATTERING_BRIGHTNESS * 0.6) * distanceFade;
				sceneOut += shadow * saturate(sunlightDiffuse);

				specularHighlight = shadow * SpecularBRDF(LdotH, NdotV, saturate(NdotL), NdotH, material.roughness, material.f0);
				specularHighlight *= oms(material.metalness * oms(albedo));
			}
		}

		#endif

		// Emissive
		// vec3 blocklightColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
		#if EMISSIVE_MODE > 0 && defined SPECULAR_MAPPING
			sceneOut += material.emissiveness * 4.0 * sdot(albedo);
		#endif
		#if EMISSIVE_MODE < 2
			// Hard-coded emissive
			vec3 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos);

			sceneOut += emissive * EMISSIVE_BRIGHTNESS;
		#endif

		// Handheld light
		// #ifdef HANDHELD_LIGHTING
		// 	if (heldBlockLightValue + heldBlockLightValue2 > 1e-4) {
		// 		float falloff = saturate(rcp(max(worldDistSquared, 1.0)) * max(heldBlockLightValue, heldBlockLightValue2));

		// 		float NdotL = saturate(dot(worldNormal, -worldDir)) * 0.8 + 0.2;
		// 		sceneOut += (falloff * NdotL * HELD_LIGHT_BRIGHTNESS) * (ao - oms(ao) * falloff * 0.7) * blocklightColor;
		// 	}
		// #endif

		// Minimal ambient light
		// sceneOut += vec3(0.77, 0.82, 1.0) * ((worldNormal.y * 0.4 + 0.6) * MINIMUM_AMBIENT_BRIGHTNESS) * ao;

		// Specular reflections
		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			if (material.hasReflections && materialID != 46u && materialID != 47u) {
				// lightmap.y = remap(0.3, 0.7, lightmap.y);

				// Specular reflections
				// specularCurrent = CalculateSpecularReflections(material, worldNormal, screenPos, worldDir, viewPos, lightmap.y, dither);

				NoiseGenerator noiseGenerator = initNoiseGenerator(uvec2(gl_FragCoord.xy), uint(frameCounter));
				vec2 atlasSize = vec2(textureSize(atlasTex, 0));

				#if RENDER_MODE == 1
					specularCurrent = specularHistory = PathTraceSpecular(material, worldPos, worldDir, normalOffset, worldNormal, noiseGenerator, atlasSize, lightmap.y);
					if (material.isRough) SpecularAccumulation(Reproject(screenPos).xy, -viewPos.z, worldNormal, material.roughness);

					// Metallic
					// material.metalness *= 0.2 * lightmap.y + 0.8;
					albedo *= oms(material.metalness);
				#else
					specularCurrent = PathTraceSpecular(material, worldPos, worldDir, normalOffset, worldNormal, noiseGenerator, atlasSize, lightmap.y);
				#endif
			}
		#else
			// Clear buffer
			specularCurrent = vec4(0.0);
		#endif

		// Apply albedo
		sceneOut *= albedo;

		#if RENDER_MODE == 1
			// Specular highlights
			sceneOut += specularHighlight;
		#endif

		// Output clamp
		sceneOut = satU16f(sceneOut);
	}
}