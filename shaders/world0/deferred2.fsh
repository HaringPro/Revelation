#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Deferred lighting and sky rendering

--------------------------------------------------------------------------------
*/

#define CLOUD_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
layout (location = 0) out vec3 sceneOut;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in mat4x3 skySH;

flat in vec3 blocklightColor;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex2; // Current indirect light

uniform sampler3D colortex3; // Combined Atmospheric LUT

uniform sampler2D colortex5; // Sky-View LUT

uniform sampler2D colortex6; // Albedo
uniform sampler2D colortex7; // Gbuffer data 0
uniform sampler2D colortex8; // Gbuffer data 1

uniform sampler2D colortex10; // Transmittance-View LUT

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int heldItemId;
uniform int heldBlockLightValue;
uniform int heldItemId2;
uniform int heldBlockLightValue2;
uniform int moonPhase;

uniform float frameTimeCounter;
uniform float nightVision;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float wetness;
uniform float wetnessCustom;
uniform float eyeAltitude;
uniform float biomeSnowySmooth;
uniform float eyeSkylightFix;
uniform float lightningFlashing;
uniform float worldTimeCounter;
uniform float timeNoon;
uniform float timeMidnight;
uniform float timeSunrise;
uniform float timeSunset;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 taaOffset;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelView;

//======// Struct //==============================================================================//

#include "/lib/utility/Material.glsl"

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"

#include "/lib/atmospherics/Global.inc"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

#include "/lib/atmospherics/Celestial.glsl"
#include "/lib/atmospherics/Clouds.glsl"

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#if AO_ENABLED > 0
	#include "/lib/lighting/AmbientOcclusion.glsl"
#endif

#include "/lib/utility/Offset.glsl"

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	float depth = sampleDepth(screenTexel);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	vec4 gbufferData0 = sampleGbufferData0(screenTexel);

	uint materialID = uint(gbufferData0.y * 255.0);

	vec3 albedoRaw = texelFetch(colortex6, screenTexel, 0).rgb;
	vec3 albedo = sRGBtoLinear(albedoRaw);

	if (depth > 0.999999 + materialID) {
		vec2 skyViewCoord = FromSkyViewLutParams(worldDir);
		vec3 skyRadiance = textureBicubic(colortex5, skyViewCoord).rgb;

		vec3 moonDisc = mix(albedo, GetLuminance(albedo) * vec3(0.7, 1.1, 1.5), 0.5) * 0.1;
		vec3 celestial = mix(RenderStars(worldDir), moonDisc, bvec3(albedo.g > 0.06)) // Use bvec3 to avoid errors with some drivers
		 + RenderSun(worldDir, worldSunVector);

		vec3 transmittance = texture(colortex10, skyViewCoord).rgb;
		sceneOut = skyRadiance + transmittance * celestial;

		#ifdef CLOUDS_ENABLED
			float dither = Bayer64Temporal(gl_FragCoord.xy);
			vec4 cloudData = RenderClouds(worldDir, skyRadiance, dither);

			sceneOut = sceneOut * cloudData.a + cloudData.rgb;
		#endif
	} else {
		sceneOut = vec3(0.0);
		worldPos += gbufferModelViewInverse[3].xyz;

		vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
		lightmap.y = isEyeInWater == 1 ? 1.0 : lightmap.y;
		vec3 flatNormal = GetFlatNormal(gbufferData0);
		#if defined MC_NORMAL_MAP
			vec3 worldNormal = GetWorldNormal(gbufferData0);
		#else
			vec3 worldNormal = flatNormal;
		#endif
		vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

		// vec4 gbufferData1 = texelFetch(colortex4, screenTexel, 0);
		// vec4 specTex = vec4(unpackUnorm2x8(gbufferData1.z), unpackUnorm2x8(gbufferData1.w));

		Material material = Material(1.0, 0.0, 0.04, 0.0, false, false);

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		float sssAmount = 0.0;
		#if SUBSERFACE_SCATTERING_MODE < 2
			// Hard-coded sss amount for certain materials
			switch (materialID) {
				case 9u: case 10u: case 11u: case 13u: case 28u: // Plants
					sssAmount = 0.45;
					NdotL = worldLightVector.y;
					break;
				case 12u: // Leaves
					sssAmount = 0.85;
					break;
				case 27u: case 37u: // Weak SSS
					sssAmount = 0.5;
					break;
				case 38u: case 51u: // Strong SSS
					sssAmount = 0.8;
					break;
				case 40u: // Particles
					sssAmount = 0.35;
					break;
			}
		#endif

		// Remap sss amount to [0, 1] range
		sssAmount = remap(64.0 * r255, 1.0, sssAmount) * eyeSkylightFix * SUBSERFACE_SCATTERING_STRENTGH;

		float dither = BlueNoiseTemporal(screenTexel);

		// Ambient occlusion
		float ao = 1.0;
		if (depth > 0.56) {
			#if AO_ENABLED > 0
				#if AO_ENABLED == 1
					ao = CalculateSSAO(screenCoord, viewPos, viewNormal, dither);
				#else
					ao = CalculateGTAO(screenCoord, viewPos, viewNormal, dither);
				#endif
			#endif
		} else depth += 0.38;

		// Cloud shadows
		#ifdef CLOUD_SHADOWS
			float cloudShadow = CalculateCloudShadow(worldPos + cameraPosition);
		#else
			float cloudShadow = 1.0 - wetness * 0.96;
		#endif

		// Sunlight
		vec3 sunlightMult = 30.0 * cloudShadow * directIlluminance;

		vec3 shadow = vec3(0.0);
		vec3 diffuseBRDF = vec3(1.0);
		vec3 specularBRDF = vec3(0.0);

		float distortFactor;
		vec3 normalOffset = flatNormal * (dotSelf(worldPos) * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
		vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortFactor);	

		float distanceFade = sqr(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

        if (distanceFade < 1e-6 && max(NdotL, sssAmount) > 1e-3) {
			vec2 blockerSearch = BlockerSearch(shadowScreenPos, dither);

			// Subsurface scattering
			if (sssAmount > 1e-4) {
				vec3 subsurfaceScattering = CalculateSubsurfaceScattering(albedo, sssAmount, blockerSearch.y, LdotV);
				// subsurfaceScattering *= eyeSkylightFix;
				sceneOut += subsurfaceScattering * sunlightMult * ao;
			}

			// Shadows
			if (NdotL > 1e-3) {
				float penumbraScale = max(blockerSearch.x / distortFactor, 2.0 / realShadowMapRes);
				shadow = PercentageCloserFilter(shadowScreenPos, dither, penumbraScale) * saturate(lightmap.y * 1e8);

				if (maxOf(shadow) > 1e-6) {
					shadow *= sunlightMult;
					#ifdef SCREEN_SPACE_SHADOWS
						shadow *= ScreenSpaceShadow(viewPos, screenPos, viewNormal, dither, sssAmount);
					#endif
					// shadow = shadow * oneMinus(distanceFade) + distanceFade;

					float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
					float NdotV = saturate(dot(worldNormal, -worldDir));
					float NdotH = maxEps((NdotL + NdotV) * halfwayNorm);
					float LdotH = LdotV * halfwayNorm + halfwayNorm;
					NdotV = max(NdotV, 1e-3);

					diffuseBRDF *= mix(DiffuseHammon(LdotV, NdotV, NdotL, NdotH, material.roughness, albedo), vec3(rPI), sssAmount * 0.75);
					specularBRDF = vec3(SPECULAR_HIGHLIGHT_BRIGHTNESS) * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(material.roughness), material.f0);
				}
			}
		} else if (NdotL > 1e-3) {
			shadow = sunlightMult;
			#ifdef SCREEN_SPACE_SHADOWS
				shadow *= ScreenSpaceShadow(viewPos, screenPos, viewNormal, dither, sssAmount);
			#endif

			float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
			float NdotV = saturate(dot(worldNormal, -worldDir));
			float NdotH = maxEps((NdotL + NdotV) * halfwayNorm);
			float LdotH = LdotV * halfwayNorm + halfwayNorm;
			NdotV = max(NdotV, 1e-3);

			diffuseBRDF *= mix(DiffuseHammon(LdotV, NdotV, NdotL, NdotH, material.roughness, albedo), vec3(rPI), sssAmount * 0.75);
			specularBRDF = vec3(SPECULAR_HIGHLIGHT_BRIGHTNESS) * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(material.roughness), material.f0);
		}

		// Sunlight diffuse
		sceneOut += shadow * diffuseBRDF;

		// Skylight and bounced light
		#ifndef SSPT_ENABLED
			if (lightmap.y > 1e-5) {
				// Skylight
				vec3 skylight = FromSphericalHarmonics(skySH, worldNormal);
				skylight = mix(skylight, directIlluminance * 0.1, wetness * 0.5);
				skylight *= worldNormal.y * 1.6 + 2.4;

				sceneOut += skylight * cube(lightmap.y) * ao;

				// Bounced light
				float bounce = CalculateFittedBouncedLight(worldNormal);
				bounce *= pow5(lightmap.y);
				sceneOut += bounce * sunlightMult * ao;
			}
		#endif

		// Global illumination
		// #ifdef SSPT_ENABLED
		// 	#ifdef SVGF_ENABLED
		// 		sceneOut += SpatialFilter(worldNormal, length(viewPos), NdotV) * (ao * 0.6 + 0.4);
		// 	#else
		// 		sceneOut += texelFetch(colortex2, screenTexel / 2, 0).rgb * (ao * 0.6 + 0.4);
		// 	#endif
		// #endif

		// Emissive & Blocklight
		vec4 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos, blocklightColor);
		#ifdef SSPT_ENABLED
			float albedoLuma = saturate(dot(albedo, vec3(0.45)));

			vec3 emissionAlbedo = normalize(maxEps(albedo));
			emissionAlbedo *= mix(inversesqrt(emissionAlbedo), vec3(1.0), fastSqrt(albedoLuma));
			emissive.rgb *= emissionAlbedo * 1.5;
		#else
			if (emissive.a * lightmap.x > 1e-5) {
				lightmap.x = CalculateBlocklightFalloff(lightmap.x);
				sceneOut += lightmap.x * (ao * oneMinus(lightmap.x) + lightmap.x) * blocklightColor * emissive.a;
			}
		#endif
		sceneOut += emissive.rgb * EMISSION_BRIGHTNESS;
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > 1e-4) {
				float falloff = rcp(max(dotSelf(worldPos), 1.0));
				sceneOut += falloff * (ao * oneMinus(falloff) + falloff) * max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS * blocklightColor;
			}
		#endif

		// Minimal ambient light
		sceneOut = max(sceneOut, vec3(MINIMUM_AMBIENT_BRIGHTNESS * ao));

		// Apply albedo
		sceneOut *= albedo;

		// Specular highlights
		sceneOut += shadow * specularBRDF;
	}
}