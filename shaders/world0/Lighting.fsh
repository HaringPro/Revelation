#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
layout(location = 0) out vec3 sceneOut;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in mat4x3 skySH;

flat in vec3 blocklightColor;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex0; // Albedo

uniform sampler2D colortex2; // Sky-View LUT

uniform sampler2D colortex3; // Gbuffer data 0
uniform sampler2D colortex4; // Gbuffer data 1

uniform sampler2D colortex10; // Transmittance-View LUT

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

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
uniform float weatherSnowySmooth;
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

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Noise.inc"

#include "/lib/atmospherics/Global.inc"
#include "/lib/atmospherics/Celestial.glsl"

#include "/lib/lighting/Sunlight.glsl"
#include "/lib/lighting/Blocklight.glsl"

#if AO_ENABLED > 0
	#include "/lib/lighting/AmbientOcclusion.glsl"
#endif


//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	float depth = sampleDepth(screenTexel);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	vec4 gbufferData0 = texelFetch(colortex3, screenTexel, 0);

	uint materialID = uint(gbufferData0.y * 255.0);

	if (depth > 0.999999 + materialID) {
		vec2 skyViewCoord = FromSkyViewLutParams(worldDir);
		sceneOut = textureBicubic(colortex2, skyViewCoord).rgb;
		vec3 transmittance = texture(colortex10, skyViewCoord).rgb;
		sceneOut += transmittance * (RenderStars(worldDir) + RenderSun(worldDir, worldSunVector));
	} else {
		sceneOut = vec3(0.0);

		vec3 albedoRaw = texelFetch(colortex0, screenTexel, 0).rgb;
		vec3 albedo = sRGBtoLinear(albedoRaw);
		worldPos += gbufferModelViewInverse[3].xyz;

		vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
		// vec3 flatNormal = GetFlatNormal(screenTexel);
		vec3 worldNormal = GetWorldNormal(screenTexel);

		// vec4 gbufferData1 = texelFetch(colortex4, screenTexel, 0);
		// vec4 specTex = vec4(unpackUnorm2x8(gbufferData1.z), unpackUnorm2x8(gbufferData1.w));

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		// Sunlight
		vec3 sunlightMult = fma(wetness, -23.0, 24.0) * directIlluminance;

		vec3 shadow = vec3(0.0);
		vec3 diffuseBRDF = vec3(1.0);
		vec3 specularBRDF = vec3(0.0);

		float distortFactor;
		vec3 normalOffset = worldNormal * fma(dotSelf(worldPos), 4e-5, 2e-2) * (2.0 - saturate(NdotL));

		vec3 shadowProjPos = WorldPosToShadowProjPosBias(worldPos + normalOffset, distortFactor);

		// float distanceFade = saturate(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

		#ifdef TAA_ENABLED
			float dither = BlueNoiseTemporal();
		#else
			float dither = InterleavedGradientNoise(gl_FragCoord.xy);
		#endif

		float ao = 1.0;
		#if AO_ENABLED > 0
			if (depth > 0.56) {
				vec3 viewNormal = mat3(gbufferModelView) * worldNormal;
				#if AO_ENABLED == 1
					ao = CalculateSSAO(screenCoord, viewPos, viewNormal, dither);
				#else
					ao = CalculateGTAO(screenCoord, viewPos, viewNormal, dither);
				#endif
			}
		#endif

		vec2 blockerSearch = BlockerSearch(shadowProjPos, dither);

		// #if TEXTURE_FORMAT == 0 && defined MC_SPECULAR_MAP
		// 	float hasSSScattering = step(64.5 / 255.0, specTex.b);
		// 	float sssAmount = remap(64.0 / 255.0, 1.0, specTex.b * hasSSScattering) * SUBSERFACE_SCATTERING_STRENTGH;
		// #else
		// 	float sssAmount = remap(64.0 / 255.0, 1.0, specTex.a) * SUBSERFACE_SCATTERING_STRENTGH;
		// #endif
		float sssAmount = 0.0;
		switch (materialID) {
			case 9u: case 10u: case 11u: case 28u: // Plants
				sssAmount = 0.55;
				break;
			case 12u: // Leaves
				sssAmount = 0.75;
				break;
			case 13u: case 27u: case 37u: // Weak SSS
				sssAmount = 0.45;
				break;
			case 38u: // Strong SSS
				sssAmount = 0.75;
				break;
		}
		sssAmount = remap(64.0 * r255, 1.0, sssAmount) * SUBSERFACE_SCATTERING_STRENTGH;

		if (sssAmount > 1e-4) {
			vec3 subsurfaceScattering = CalculateSubsurfaceScattering(albedo, sssAmount, blockerSearch.y, LdotV);
			subsurfaceScattering *= eyeSkylightFix;
			sceneOut += subsurfaceScattering * sunlightMult * ao;
			sunlightMult *= 1.0 - sssAmount * 0.5;
		}

		if (NdotL > 1e-3) {
			float penumbraScale = max(blockerSearch.x / distortFactor, 2.0 / realShadowMapRes);
			shadow = PercentageCloserFilter(shadowProjPos, dither, penumbraScale);

			if (maxOf(shadow) > 1e-6) {
				float NdotV = saturate(dot(worldNormal, -worldDir));
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = (NdotL + NdotV) * halfwayNorm;
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				#ifdef SCREEN_SPACE_SHADOWS
					shadow *= ScreenSpaceShadow(viewPos, screenPos, dither);
				#endif
				diffuseBRDF *= DiffuseHammon(LdotV, max(NdotV, 1e-3), NdotL, NdotH, 1., albedo);

				specularBRDF = vec3(SPECULAR_HIGHLIGHT_BRIGHTNESS) * SpecularBRDF(LdotH, max(NdotV, 1e-3), NdotL, NdotH, sqr(1.), .04);

				shadow *= saturate(lightmap.y * 1e8);
				shadow *= sunlightMult;
			}
		}

		sceneOut += shadow * diffuseBRDF;

		if (lightmap.y > 1e-5) {
			// Skylight
			vec3 skylight = FromSphericalHarmonics(skySH, worldNormal);
			skylight *= worldNormal.y * 1.2 + 1.8;

			sceneOut += skylight * cube(lightmap.y) * ao;

			// Bounced light
			float bounce = CalculateFittedBouncedLight(worldNormal);
			if (isEyeInWater == 0) bounce *= pow5(lightmap.y);
			sceneOut += bounce * sunlightMult * ao;
		}

		// Emissive & Blocklight
		vec4 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos);
		if (emissive.a * lightmap.x > 1e-5) {
			lightmap.x = CalculateBlocklightFalloff(lightmap.x);
			sceneOut += lightmap.x * (ao * oneMinus(lightmap.x) + lightmap.x) * blocklightColor * emissive.a;
		}
		sceneOut += emissive.rgb * 3.0;
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > 1e-4) {
				float falloff = rcp(max(dotSelf(worldPos), 1.0));
				sceneOut += falloff * (ao * oneMinus(falloff) + falloff) * max(heldBlockLightValue, heldBlockLightValue2) * HELDL_IGHT_BRIGHTNESS * blocklightColor;
			}
		#endif

		sceneOut *= albedo;

		// Specular highlights
		sceneOut += shadow * specularBRDF;
	}
}
