/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute specular reflections

--------------------------------------------------------------------------------
*/

#define PASS_SPECULAR_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 3 */
out vec4 specularOut;

//======// Uniform //=============================================================================//

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

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
	#include "/lib/surface/BRDF.glsl"
	#include "/lib/surface/Reflection.glsl"
#endif

//======// Main //================================================================================//
void main() {
	specularOut = vec4(0.0);

	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		ivec2 texelPos = ivec2(gl_FragCoord.xy);
		vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, loadDepth0(texelPos));

		if (screenPos.z > 1.0 - EPS) discard;

		// Hand-depth correction
		if (screenPos.z < 0.56) {
			screenPos.z = screenPos.z * rcp(MC_HAND_DEPTH) + (0.5 - 0.5 / MC_HAND_DEPTH);
		}

    	Material material = GetMaterialData(Unpack2x8U(loadMaterialPack(texelPos).z));

		// Specular reflections
		if (material.specularMask) {
			vec3 viewPos = ScreenToViewSpace(screenPos);

			#if defined LOD_MOD
				bool lodTerrainMask = screenPos.z > 1.0 - EPS;
				if (lodTerrainMask) {
					screenPos.z = loadDepth0Lod(texelPos);
					viewPos = ScreenToViewSpaceLod(screenPos);
				}
			#endif

			vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
			vec3 worldDir = normalize(worldPos);
			worldPos += gbufferModelViewInverse[3].xyz;

			vec3 worldNormal = FetchSurfaceNormal(texelPos);

			vec2 lightmap = Unpack2x8U(loadMaterialPack(texelPos).x);
			lightmap.y = linearstep(0.3, 0.7, lightmap.y);

			float dither = BlueNoise(texelPos, frameCounter);
			specularOut = CalculateSpecularReflections(material, worldNormal, screenPos, worldDir, viewPos, lightmap.y, dither);
		}
	#endif
}