#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute refraction, combine translucent, reflections and fog

--------------------------------------------------------------------------------
*/

#define PASS_COMPOSITE

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

//======// Uniform //=============================================================================//

uniform sampler2D colortex0;

uniform usampler2D colortex11; // Volumetric Fog, linear depth

#if defined DEPTH_OF_FIELD && CAMERA_FOCUS_MODE == 0
    uniform float centerDepthSmooth;
#endif

#include "/lib/universal/Uniform.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/CommonFog.glsl"

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

	float depth = loadDepth0(screenTexel);
	float sDepth = loadDepth1(screenTexel);

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);
	vec3 sViewPos = ScreenToViewSpace(vec3(screenCoord, sDepth));
	#if defined DISTANT_HORIZONS
		if (depth > 0.999999) {
			depth = screenPos.z = loadDepth0DH(screenTexel);
			viewPos = ScreenToViewSpaceDH(screenPos);
		}
		if (sDepth > 0.999999) {
			sDepth = loadDepth1DH(screenTexel);
			sViewPos = ScreenToViewSpaceDH(vec3(screenCoord, sDepth));
		}
	#endif

	float viewDistance = length(viewPos);
	float transparentDepth = distance(viewPos, sViewPos);

	vec4 gbufferData1 = loadGbufferData1(screenTexel);

	vec2 refractedCoord = screenCoord;
	ivec2 refractedTexel = screenTexel;
	bool waterMask = materialID == 3u;

	if (materialID == 2u || waterMask) {
		vec3 viewNormal = mat3(gbufferModelView) * decodeUnitVector(Unpack2x8U(gbufferData0.z));
		#ifdef RAYTRACED_REFRACTION
			refractedCoord = CalculateRefractedCoord(waterMask, viewPos, viewNormal, screenPos);
		#else	
			refractedCoord = CalculateRefractedCoord(waterMask, viewPos, viewNormal, screenPos, gbufferData1, transparentDepth);
		#endif
		refractedTexel = uvToTexel(refractedCoord);

		depth = loadDepth0(refractedTexel);
		sDepth = loadDepth1(refractedTexel);

		// gbufferData0 = loadGbufferData0(refractedTexel);
		viewPos = ScreenToViewSpace(vec3(refractedCoord, depth));
		sViewPos = ScreenToViewSpace(vec3(refractedCoord, sDepth));
		#if defined DISTANT_HORIZONS
			if (depth > 0.999999) {
				depth = loadDepth0DH(refractedTexel);
				viewPos = ScreenToViewSpaceDH(vec3(refractedCoord, depth));
			}
			if (sDepth > 0.999999) {
				sDepth = loadDepth1DH(refractedTexel);
				sViewPos = ScreenToViewSpaceDH(vec3(refractedCoord, sDepth));
			}
		#endif
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
			Material material = GetMaterialData(gbufferData1.xy);
		#endif

		// Water fog
		if (waterMask && isEyeInWater == 0) {
			float waterDepth = distance(viewPos, sViewPos);
			mat2x3 waterFog = CalculateWaterFog(skyLightmap, max(transparentDepth, waterDepth), LdotV);
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
				reflectionData.rgb *= oms(material.metalness * oms(albedo));
				sceneOut += reflectionData.rgb;
			}
		#endif

		// Border fog
		#ifdef BORDER_FOG
			#if defined DISTANT_HORIZONS
				#define far float(dhRenderDistance)
			#endif

			if (isEyeInWater == 0) {
				float density = saturate(1.0 - exp2(-pow8(sdot(worldPos.xz) * rcp(far * far)) * BORDER_FOG_FALLOFF));
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
			mat2x3 volFogData = VolumetricFogSpatialUpscale(screenTexel >> 1, -viewPos.z);
			sceneOut = ApplyFog(sceneOut, volFogData);
			bloomyFogTrans = mean(volFogData[1]);
		}
	#endif

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 waterFog = VolumetricFogSpatialUpscale(screenTexel >> 1, -viewPos.z);
		#else
			mat2x3 waterFog = CalculateWaterFog(saturate(eyeSkylightSmooth + 0.2), viewDistance, LdotV);
		#endif
		sceneOut = ApplyFog(sceneOut, waterFog);
		bloomyFogTrans = mean(waterFog[1]);
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