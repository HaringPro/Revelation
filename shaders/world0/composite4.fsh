#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute refraction, combine translucent, reflections and fog

--------------------------------------------------------------------------------
*/

#define PROGRAM_COMPOSITE_4

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

#ifdef DEPTH_OF_FIELD
/* RENDERTARGETS: 4,8 */
#else
/* RENDERTARGETS: 0,8 */
#endif

layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogTrans;

//======// Input //===============================================================================//

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Uniform //=============================================================================//

uniform sampler2D colortex11; // Volumetric Fog scattering
uniform sampler2D colortex12; // Volumetric Fog transmittance

#if defined DEPTH_OF_FIELD && CAMERA_FOCUS_MODE == 0
    uniform float centerDepthSmooth;
#endif

#include "/lib/universal/Uniform.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"

#include "/lib/atmospherics/Global.glsl"
#include "/lib/atmospherics/CommonFog.glsl"

#include "/lib/SpatialUpscale.glsl"

#include "/lib/water/WaterFog.glsl"

#include "/lib/surface/BRDF.glsl"
#include "/lib/surface/Reflection.glsl"
#include "/lib/surface/Refraction.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
	uvec4 gbufferData0 = loadGbufferData0(screenTexel);

	uint materialID = gbufferData0.y;

	float depth = FetchDepthFix(screenTexel);
	float sDepth = FetchDepthSoildFix(screenTexel);

	#ifdef BORDER_FOG
		bool doBorderFog = depth < 1.0 && isEyeInWater == 0;
	#endif

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);
	vec3 sViewPos = ScreenToViewSpace(vec3(screenCoord, sDepth));

	float viewDistance = length(viewPos);
	float transparentDepth = distance(viewPos, sViewPos);

	vec4 gbufferData1 = loadGbufferData1(screenTexel);

	vec2 refractedCoord = screenCoord;
	ivec2 refractedTexel = screenTexel;
	bool waterMask = false;

	if (materialID == 2u || materialID == 3u) {
		vec3 viewNormal = mat3(gbufferModelView) * decodeUnitVector(Unpack2x8U(gbufferData0.z));
		#ifdef RAYTRACED_REFRACTION
			refractedCoord = CalculateRefractedCoord(materialID == 3u, viewPos, viewNormal, screenPos);
		#else	
			refractedCoord = CalculateRefractedCoord(materialID == 3u, viewPos, viewNormal, screenPos, gbufferData1, transparentDepth);
		#endif
		refractedTexel = uvToTexel(refractedCoord);

		depth = loadDepth0(refractedTexel);

		gbufferData0 = loadGbufferData0(refractedTexel);
		viewPos = ScreenToViewSpace(vec3(refractedCoord, depth));
		waterMask = gbufferData0.y == 3u || materialID == 3u;
	}

    sceneOut = loadSceneColor(refractedTexel);
	vec3 worldNormal = FetchWorldNormal(gbufferData0);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	float LdotV = dot(worldLightVector, worldDir);

	if (depth < 1.0 || waterMask) {
		worldPos += gbufferModelViewInverse[3].xyz;
		float skyLightmap = Unpack2x8UY(gbufferData0.x);

		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			vec4 specularTex = vec4(Unpack2x8(gbufferData1.x), vec2(0.0));
			Material material = GetMaterialData(specularTex);
		#endif

		// Water fog
		if (waterMask && isEyeInWater == 0) {
			float waterDepth = abs(viewPos.z + ScreenToViewDepth(loadDepth1(refractedTexel)));
			FogData waterFog = CalculateWaterFog(skyLightmap, max(transparentDepth, waterDepth), LdotV);
			sceneOut = ApplyFog(sceneOut, waterFog);
		}

		if (waterMask) { // Water
			// Specular lighting of water
			vec4 blendedData = texelFetch(colortex1, screenTexel, 0);
			#if TRANSLUCENT_LIGHTING_BLENDED_MODE == 1
				blendedData.rgb -= sceneOut * blendedData.a;
			#else
				blendedData.rgb = waterMask && isEyeInWater == 1 ? blendedData.rgb - sceneOut * blendedData.a : blendedData.rgb;
			#endif

			sceneOut += blendedData.rgb;
		} else if (materialID == 2u) { // Glass
			// Glass tint
			vec4 translucents = vec4(Unpack2x8(gbufferData1.x), Unpack2x8(gbufferData1.y));
			sceneOut *= exp2(5.0 * (translucents.rgb - 1.0) * approxSqrt(approxSqrt(translucents.a)));

			// Specular and diffuse lighting of glass
			vec4 blendedData = texelFetch(colortex1, screenTexel, 0);
			#if TRANSLUCENT_LIGHTING_BLENDED_MODE == 1
				blendedData.rgb -= sceneOut * blendedData.a;
			#endif

			sceneOut += blendedData.rgb;
		} else if (materialID == 46u || materialID == 51u) {
			// Specular reflections of slime and ender portal
			vec4 reflections = CalculateSpecularReflections(worldNormal, skyLightmap, screenPos, worldDir, viewPos);
			sceneOut += (reflections.rgb - sceneOut) * reflections.a;
		}
		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			else if (material.hasReflections) {
				// Specular reflections of other materials
				vec4 reflectionData = texelFetch(colortex1, refractedTexel, 0);

				vec3 albedo = sRGBtoLinear(loadAlbedo(screenTexel));
				reflectionData.rgb *= oneMinus(material.metalness * oneMinus(albedo));
				sceneOut += reflectionData.rgb;
			}
		#endif

		// Border fog
		#ifdef BORDER_FOG
			if (doBorderFog) {
				float density = saturate(1.0 - exp2(-sqr(pow4(dotSelf(worldPos.xz) * rcp(far * far))) * BORDER_FOG_FALLOFF));
				density *= exp2(-5.0 * curve(saturate(worldDir.y * 3.0)));

				vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(worldDir)).rgb;
				sceneOut = mix(sceneOut, skyRadiance, density);
			}
		#endif
	}

	// Initialize bloomyFogTrans
	bloomyFogTrans = 1.0;

	// Volumetric fog
	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			FogData volFogData = VolumetricFogSpatialUpscale(gl_FragCoord.xy, -sViewPos.z);
			sceneOut = ApplyFog(sceneOut, volFogData);
			bloomyFogTrans = dot(volFogData.transmittance, vec3(0.333333));
		}
	#endif

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			FogData waterFog = VolumetricFogSpatialUpscale(gl_FragCoord.xy, -sViewPos.z);
		#else
			FogData waterFog = CalculateWaterFog(saturate(eyeSkylightSmooth + 0.2), viewDistance, LdotV);
		#endif
		sceneOut = ApplyFog(sceneOut, waterFog);
		bloomyFogTrans = dot(waterFog.transmittance, vec3(0.333333));
	}

	RenderVanillaFog(sceneOut, bloomyFogTrans, viewDistance);

	#ifdef DEBUG_CLOUD_SHADOWS
		sceneOut = vec3(textureBicubic(colortex10, screenCoord).a);
	#endif

	#if DEBUG_NORMALS == 1
		sceneOut = worldNormal * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneOut = FetchFlatNormal(gbufferData0) * 0.5 + 0.5;
	#endif
}