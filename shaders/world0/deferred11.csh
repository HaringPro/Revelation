#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute specular reflections (and clear colorimg3)

--------------------------------------------------------------------------------
*/

#define RANDOM_NOISE
#define gl_FragCoord gl_GlobalInvocationID

layout (local_size_x = 16, local_size_y = 16) in;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
	const vec2 workGroupsRender = vec2(1.0f, 1.0f);
#else
	const vec2 workGroupsRender = vec2(0.5f, 0.5f);
#endif

writeonly restrict uniform image2D colorimg3; // Current indirect light

//======// Uniform //=============================================================================//

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
	uniform sampler2D noisetex;

	uniform sampler2D colortex4;
	uniform sampler2D colortex5; // Sky-View LUT

	uniform sampler2D colortex7; // Gbuffer data 0
	uniform sampler2D colortex8; // Gbuffer data 1

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

	#include "/lib/surface/BRDF.glsl"

	#include "/lib/surface/ScreenSpaceRaytracer.glsl"

	vec4 CalculateSpecularReflections(Material material, in vec3 viewNormal, in vec3 screenPos, in vec3 viewPos, in float skylight, in float dither) {
		skylight = smoothstep(0.3, 0.8, cube(skylight));
		vec3 viewDir = normalize(viewPos);

		vec3 rayDir;
		float LdotH;
		#ifdef ROUGH_REFLECTIONS
			if (material.isRough) {
				mat3 tbnMatrix;
				tbnMatrix[0] = normalize(cross(gbufferModelView[1].xyz, viewNormal));
				tbnMatrix[1] = cross(viewNormal, tbnMatrix[0]);
				tbnMatrix[2] = viewNormal;

				vec3 tangentViewDir = -viewDir * tbnMatrix;
				vec3 facetNormal = tbnMatrix * sampleGGXVNDF(tangentViewDir, material.roughness, RandNext2F());
				LdotH = dot(facetNormal, -viewDir);
				rayDir = viewDir + facetNormal * LdotH * 2.0;
			} else
		#endif
		{
			LdotH = dot(viewNormal, -viewDir);
			rayDir = viewDir + viewNormal * LdotH * 2.0;
		}

		float NdotL = dot(viewNormal, rayDir);
		if (NdotL < 1e-6) return vec4(0.0);

		bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, uint(RAYTRACE_SAMPLES * oneMinus(material.roughness)), screenPos);

		vec3 reflection;
		if (hit) {
			// reflection = textureLod(colortex4, screenPos.xy * viewPixelSize * 0.5, 8.0 * fastSqrt(material.roughness)).rgb;
			reflection = texelFetch(colortex4, ivec2(screenPos.xy * 0.5), 0).rgb;
		} else if (skylight > 1e-3) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld) + vec2(0.0, 0.5)).rgb;

			reflection = skyRadiance * skylight;
		}

		if (any(isnan(reflection))) reflection = vec3(0.0);

		float dist = 0.0;
		vec3 brdf = vec3(1.0);

		float NdotV = maxEps(dot(viewNormal, -viewDir));
		if (material.isRough || wetnessCustom > 1e-2) {
			float alpha2 = material.roughness * material.roughness;
			float G2 = G2SmithGGX(NdotV, NdotL, alpha2);
			float G1Inverse = G1SmithGGXInverse(NdotV, alpha2);

			brdf *= G2 * G1Inverse;
			vec3 reflectViewPos = ScreenToViewSpace(vec3(screenPos.xy * viewPixelSize, sampleDepth(ivec2(screenPos.xy))));
			float rDist = distance(reflectViewPos, viewPos);

			dist = saturate(max(rDist * 2.0, material.roughness * 3.0));
		}

		// #if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			if (material.isHardcodedMetal) {
				brdf = FresnelConductor(LdotH, material.hardcodedMetalCoeff[0], material.hardcodedMetalCoeff[1]);
			} else if (material.metalness > 0.5) {
				brdf *= FresnelSchlick(LdotH, material.f0);
			} else
		// #endif
		{ brdf *= FresnelDielectric(LdotH, material.f0); }

		return vec4(reflection * brdf, dist);
	}
#endif

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_GlobalInvocationID.xy);

	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 gbufferData1 = sampleGbufferData1(screenTexel);
		vec4 specularTex = vec4(unpackUnorm2x8(gbufferData1.x), unpackUnorm2x8(gbufferData1.y));
		Material material = GetMaterialData(specularTex);

		if (material.hasReflections) {
			vec2 screenCoord = vec2(gl_GlobalInvocationID.xy) * viewPixelSize;

			vec4 gbufferData0 = sampleGbufferData0(screenTexel);
			vec3 viewNormal = mat3(gbufferModelView) * FetchWorldNormal(gbufferData0);

			vec3 screenPos = vec3(screenCoord, FetchDepthFix(screenTexel));
			vec3 viewPos = ScreenToViewSpace(screenPos);
			float skyLightmap = unpackUnorm2x8Y(gbufferData0.x);

			float dither = InterleavedGradientNoiseTemporal(gl_GlobalInvocationID.xy);
			vec4 reflectionData = CalculateSpecularReflections(material, viewNormal, screenPos, viewPos, skyLightmap, dither);

			imageStore(colorimg3, screenTexel, reflectionData);
		} else
	#endif
	{ imageStore(colorimg3, screenTexel, vec4(0.0)); }
}