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

flat in vec3 blocklightColor;

//======// Uniform //=============================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

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
		vec3 albedoRaw = texelFetch(colortex0, screenTexel, 0).rgb;
		vec3 albedo = sRGBtoLinear(albedoRaw);
		worldPos += gbufferModelViewInverse[3].xyz;

		#ifdef TAA_ENABLED
			float dither = BlueNoiseTemporal();
		#else
			float dither = InterleavedGradientNoise(gl_FragCoord.xy);
		#endif

		vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
		// vec3 flatNormal = GetFlatNormal(screenTexel);
		vec3 worldNormal = GetWorldNormal(screenTexel);

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		// Sunlight
		vec3 sunlightMult = fma(wetness, -19.0, 20.0) * directIlluminance;

		vec3 shadow = vec3(0.0);
		vec3 diffuseBRDF = vec3(1.0);
		vec3 specularBRDF = vec3(0.0);

		float distortFactor;
		vec3 normalOffset = worldNormal * fma(dotSelf(worldPos), 4e-5, 2e-2) * (2.0 - saturate(NdotL));

		vec3 shadowProjPos = WorldPosToShadowProjPosBias(worldPos + normalOffset, distortFactor);	

		// float distanceFade = saturate(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

		vec2 blockerSearch = BlockerSearch(shadowProjPos, dither);

		if (NdotL > 1e-3) {
			float penumbraScale = max(blockerSearch.x / distortFactor, 2.0 / realShadowMapRes);
			shadow = PercentageCloserFilter(shadowProjPos, dither, penumbraScale);

			if (maxOf(shadow) > 1e-6) {
				float NdotV = saturate(dot(worldNormal, -worldDir));
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = (NdotL + NdotV) * halfwayNorm;
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				#ifdef SCREEN_SPACE_SHADOWS
					shadow *= ScreenSpaceShadow(viewPos, screenPos, dither, 0.);
				#endif
				diffuseBRDF *= DiffuseHammon(LdotV, max(NdotV, 1e-3), NdotL, NdotH, 1., albedo);

				specularBRDF = vec3(SPECULAR_HIGHLIGHT_BRIGHTNESS) * SpecularBRDF(LdotH, max(NdotV, 1e-3), NdotL, NdotH, sqr(1.), .04);

				shadow *= saturate(lightmap.y * 1e8);
				shadow *= sunlightMult;
			}
		}

		sceneOut += shadow * diffuseBRDF;

		float bounce = CalculateFittedBouncedLight(worldNormal);
		if (isEyeInWater == 0) bounce *= pow5(lightmap.y);
		sceneOut += bounce * sunlightMult;

		// Skylight
		if (lightmap.y > 1e-5) {
			// vec3 skylight = FromSH(skySH, worldNormal);
			vec3 skylight = mix(skyIlluminance * 0.6, directIlluminance * 0.2, wetness * 0.7);
			skylight *= worldNormal.y * 1.2 + 1.8;

			sceneOut += skylight * cube(lightmap.y);
		}

		// Emissive & Blocklight
		vec4 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos);
		sceneOut += CalculateBlocklightFalloff(lightmap.x) * blocklightColor * emissive.a;
		sceneOut += emissive.rgb;

		sceneOut *= albedo;

		// Specular highlights
		sceneOut += shadow * specularBRDF;
	}
}