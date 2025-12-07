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

/* RENDERTARGETS: 0,12 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogMask;

//======// Uniform //=============================================================================//

uniform usampler2D colortex11; // Volumetric Fog, linear depth

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Bruneton08.glsl"

#include "/lib/atmosphere/Rainbow.glsl"
#include "/lib/atmosphere/CommonFog.glsl"

#include "/lib/SpatialUpscale.glsl"

#include "/lib/water/WaterFog.glsl"

#include "/lib/surface/BRDF.glsl"
#include "/lib/surface/Refraction.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	float depth = loadDepth0(screenTexel);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);
	#if defined LOD_MOD
		if (depth > 1.0 - EPS) {
			depth = screenPos.z = loadDepth0Lod(screenTexel);
			viewPos = ScreenToViewSpaceLod(screenPos);
		}
	#endif

	uvec4 materialPack = loadMaterialPack(screenTexel);

	uint materialID = materialPack.y;
	bool glassMask = materialID == 2u;
	bool waterMask = materialID == 3u;

	// Process refraction
	ivec2 refractedTexel = screenTexel;
	if (glassMask || waterMask) {
		vec3 viewNormal = mat3(gbufferModelView) * FetchSurfaceNormal(screenTexel);

		#ifdef RAYTRACED_REFRACTION
			vec2 refractedCoord = CalculateRefractedCoord(waterMask, viewPos, viewNormal, screenPos);
		#else
			vec3 viewFlatNormal = mat3(gbufferModelView) * FetchGeometryNormal(screenTexel);
			viewNormal -= float(waterMask) * viewFlatNormal; // Fix water refraction artifacts

			float depth1 = loadDepth1(screenTexel);
			vec3 viewPos1 = ScreenToViewSpace(vec3(screenCoord, depth1));
			#if defined LOD_MOD
				if (depth1 > 1.0 - EPS) {
					depth1 = loadDepth1Lod(screenTexel);
					viewPos1 = ScreenToViewSpaceLod(vec3(screenCoord, depth1));
				}
			#endif
			vec2 refractedCoord = CalculateRefractedCoord(waterMask, viewPos, viewNormal, screenPos, distance(viewPos, viewPos1));
		#endif

		refractedTexel = uvToTexel(refractedCoord);
	}

    sceneOut = loadSceneMain(refractedTexel);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	if (depth < 1.0) {
		vec4 translucent = ExtractSpecularTex(materialPack);

		// Particle translucent
		if (materialID == 500u) {
			vec3 diffuseLight = texelFetch(colortex3, screenTexel, 0).rgb;
			vec3 albedo = sRGBtoLinear(translucent.rgb);
			sceneOut = mix(sceneOut, albedo * diffuseLight, translucent.a);
		}

		// Translucent
		if (glassMask || waterMask) {
			if (glassMask) {
				// Absorption
				vec3 absorption = log2(translucent.rgb);
				absorption *= 2.0 * sqrt2(translucent.a);
				sceneOut *= exp2(absorption);

				// Emissive
				sceneOut += (2.0 * EMISSIVE_BRIGHTNESS) * Unpack2x8UX(materialPack.x) * cube(translucent.rgb * translucent.a);
			}

			// Apply specular lighting
			vec4 specularLight = texelFetch(colortex3, screenTexel, 0);
			sceneOut = sceneOut * specularLight.a + specularLight.rgb;
		}

		// Border fog
		#ifdef BORDER_FOG
			#if defined LOD_MOD
				#define far float(lodRenderDistance)
			#endif

			if (isEyeInWater == 0) {
				float density = saturate(1.0 - exp2(-pow8(sdot(worldPos.xz) * rcp(far * far)) * BORDER_FOG_FALLOFF));
				density *= exp2(-4.0 * curve(saturate(worldDir.y * 3.0)));

				vec3 skyRadiance = GetSkyRadiance(worldDir, worldSunVector);
				sceneOut = mix(sceneOut, skyRadiance, density);
			}
		#endif
	}

	// Initialize
	bloomyFogMask = 1.0;

	// Volumetric fog
	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			mat2x3 volFogData = VolumetricFogSpatialUpscale(screenTexel >> 1, -viewPos.z);
			sceneOut = ApplyFog(sceneOut, volFogData);
			bloomyFogMask = mean(volFogData[1]);
		}
	#endif

	float viewDistance = length(viewPos);
	float LdotV = dot(worldLightVector, worldDir);

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 waterFog = VolumetricFogSpatialUpscale(screenTexel >> 1, -viewPos.z);
		#else
			mat2x3 waterFog = AnalyticWaterFog(eyeSkylightSmooth, viewDistance, LdotV);
		#endif
		sceneOut = ApplyFog(sceneOut, waterFog);
		bloomyFogMask = mean(waterFog[1]);
	}

	// Vanilla fog
	RenderVanillaFog(sceneOut, bloomyFogMask, viewDistance);

	#if DEBUG_NORMALS == 1
		sceneOut = FetchSurfaceNormal(screenTexel) * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneOut = FetchGeometryNormal(screenTexel) * 0.5 + 0.5;
	#endif
}