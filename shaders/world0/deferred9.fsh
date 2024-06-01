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

flat in vec3 sunIlluminance;
flat in vec3 moonIlluminance;

flat in vec3 blocklightColor;

//======// Uniform //=============================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform sampler2D noisetex;

uniform sampler2D colortex0;
uniform sampler3D colortex1;

uniform sampler2D colortex3;
uniform sampler2D colortex4;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

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

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int heldItemId;
uniform int heldBlockLightValue;
uniform int heldItemId2;
uniform int heldBlockLightValue2;
uniform int moonPhase;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelView;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 taaOffset;

//======// Struct //==============================================================================//

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Noise.inc"

#include "/lib/atmospherics/Common.inc"

#include "/lib/atmospherics/Celestial.glsl"

#include "/lib/lighting/Sunlight.glsl"

//======// Main //================================================================================//
void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	float depth = sampleDepth(texel);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	vec4 gbufferData0 = texelFetch(colortex3, texel, 0);

	uint materialID = uint(gbufferData0.y * 255.0);

	if (depth > 0.999999 + gbufferData0.y * 1e6) {
		vec3 transmittance;
		sceneOut = GetSkyRadiance(atmosphereModel, worldDir, worldSunVector, transmittance) * 6.0;
		sceneOut += transmittance * (RenderStars(worldDir) + RenderSun(worldDir, worldSunVector));
	} else {
		vec3 albedo = sRGBtoLinear(texelFetch(colortex0, texel, 0).rgb);
		worldPos += gbufferModelViewInverse[3].xyz;

		#ifdef TAA_ENABLED
			float dither = BlueNoiseTemporal();
		#else
			float dither = InterleavedGradientNoise(gl_FragCoord.xy);
		#endif

		vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
		vec3 flatNormal = GetFlatNormal(texel);
		vec3 worldNormal = GetWorldNormal(texel);

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		// Sunlight
		vec3 sunlightMult = 9.0 * directIlluminance;

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
			vec3 skylight = skyIlluminance * 0.6;
			skylight *= worldNormal.y * 0.4 + 0.6;

			sceneOut += skylight * cube(lightmap.y);
		}

		// Emissive & Blocklight
		sceneOut += 2.0 * float(materialID == 20u || materialID == 46u) + CalculateBlocklightFalloff(lightmap.x) * blocklightColor * 4.0;
		sceneOut *= albedo;

		// Specular highlights
		sceneOut += shadow * specularBRDF;
	}
}