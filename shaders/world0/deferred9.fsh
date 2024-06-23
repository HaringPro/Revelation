#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Deferred lighting and sky rendering

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.glsl"

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

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"

#include "/lib/atmospherics/Global.inc"
#include "/lib/atmospherics/Celestial.glsl"

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

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
	vec4 gbufferData0 = sampleGbufferData0(screenTexel);

	uint materialID = uint(gbufferData0.y * 255.0);

	vec3 albedoRaw = texelFetch(colortex6, screenTexel, 0).rgb;
	vec3 albedo = sRGBtoLinear(albedoRaw);

	if (depth > 0.999999 + materialID) {
		vec2 skyViewCoord = FromSkyViewLutParams(worldDir);
		sceneOut = textureBicubic(colortex5, skyViewCoord).rgb;

		vec3 moonDisc = mix(albedo, GetLuminance(albedo) * vec3(0.7, 1.1, 1.5), 0.5) * 0.1;
		vec3 celestial = mix(RenderStars(worldDir), moonDisc, albedo.g > 0.06) + RenderSun(worldDir, worldSunVector);

		vec3 transmittance = texture(colortex10, skyViewCoord).rgb;
		sceneOut += transmittance * celestial;
	} else {
		sceneOut = vec3(0.0);
		worldPos += gbufferModelViewInverse[3].xyz;

		vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
		lightmap.y = isEyeInWater == 1 ? 1.0 : lightmap.y;
		// vec3 flatNormal = GetFlatNormal(screenTexel);
		vec3 worldNormal = GetWorldNormal(gbufferData0);

		// vec4 gbufferData1 = texelFetch(colortex4, screenTexel, 0);
		// vec4 specTex = vec4(unpackUnorm2x8(gbufferData1.z), unpackUnorm2x8(gbufferData1.w));

		#ifdef TAA_ENABLED
			float dither = BlueNoiseTemporal(screenTexel);
		#else
			float dither = BlueNoise(screenTexel);
		#endif

		float ao = 1.0;
		if (depth > 0.56) {
			#if AO_ENABLED > 0
				vec3 viewNormal = mat3(gbufferModelView) * worldNormal;
				#if AO_ENABLED == 1
					ao = CalculateSSAO(screenCoord, viewPos, viewNormal, dither);
				#else
					ao = CalculateGTAO(screenCoord, viewPos, viewNormal, dither);
				#endif
			#endif
		} else depth += 0.38;

		// Sunlight
		vec3 sunlightMult = fma(wetness, -23.5, 24.0) * directIlluminance;

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		vec3 shadow = vec3(0.0);
		vec3 diffuseBRDF = vec3(1.0);
		vec3 specularBRDF = vec3(0.0);

		float distortFactor;
		vec3 shadowScreenPos = WorldToShadowScreenSpaceBias(worldPos, worldNormal, distortFactor);	

		// float distanceFade = saturate(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

		float sssAmount = 0.0;
		switch (materialID) {
			case 9u: case 10u: case 11u: case 13u: case 28u: // Plants
				sssAmount = 0.55;
				NdotL = worldLightVector.y;
				break;
			case 12u: // Leaves
				sssAmount = 0.8;
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
		sssAmount = remap(64.0 * r255, 1.0, sssAmount) * eyeSkylightFix * SUBSERFACE_SCATTERING_STRENTGH;

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
				float NdotV = saturate(dot(worldNormal, -worldDir));
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = maxEps((NdotL + NdotV) * halfwayNorm);
				float LdotH = LdotV * halfwayNorm + halfwayNorm;
				NdotV = max(NdotV, 1e-3);

				shadow *= sunlightMult;
				#ifdef SCREEN_SPACE_SHADOWS
					shadow *= ScreenSpaceShadow(viewPos, screenPos, dither, sssAmount);
				#endif

				diffuseBRDF *= mix(DiffuseHammon(LdotV, NdotV, NdotL, NdotH, 1., albedo), vec3(rPI), sssAmount * 0.75);
				specularBRDF = vec3(SPECULAR_HIGHLIGHT_BRIGHTNESS) * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(1.), .04);
			}
		}

		sceneOut += shadow * diffuseBRDF;

		if (lightmap.y > 1e-5) {
			// Skylight
			vec3 skylight = FromSphericalHarmonics(skySH, worldNormal);
			skylight = mix(skylight, directIlluminance * 0.05, wetness * 0.5);
			skylight *= worldNormal.y * 1.2 + 1.8;

			sceneOut += skylight * cube(lightmap.y) * ao;

			// Bounced light
			float bounce = CalculateFittedBouncedLight(worldNormal);
			bounce *= pow5(lightmap.y);
			sceneOut += bounce * sunlightMult * ao;
		}

		// Emissive & Blocklight
		vec4 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos, blocklightColor);
		if (emissive.a * lightmap.x > 1e-5) {
			lightmap.x = CalculateBlocklightFalloff(lightmap.x);
			sceneOut += lightmap.x * (ao * oneMinus(lightmap.x) + lightmap.x) * blocklightColor * emissive.a;
		}
		sceneOut += emissive.rgb * EMISSION_BRIGHTNESS;
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > 1e-4) {
				float falloff = rcp(max(dotSelf(worldPos), 1.0));
				sceneOut += falloff * (ao * oneMinus(falloff) + falloff) * max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS * blocklightColor;
			}
		#endif

		sceneOut *= albedo;

		// Specular highlights
		sceneOut += shadow * specularBRDF;
	}
}