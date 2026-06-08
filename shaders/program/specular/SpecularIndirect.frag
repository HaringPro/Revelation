/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Compute specular reflections

--------------------------------------------------------------------------------
*/

#define PASS_SPECULAR_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec4 specularOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"

#include "/lib/surface/Material.glsl"

#include "/lib/lighting/BRDF.glsl"
#include "/lib/lighting/SSR.glsl"

//======// Main //================================================================================//
void main() {
	specularOut = vec4(0.0);

	ivec2 texelPos = ivec2(gl_FragCoord.xy);

	Material material = GetMaterialData(Unpack2x8U(loadMaterialPack(texelPos).z));
	if (material.specularMask) {
		vec3 screenPos = vec3(gl_FragCoord.xy * scaledTexelSize, loadDepth0(texelPos));
		if (screenPos.z > 1.0 - EPS) discard;

		// Hand-depth correction
		if (screenPos.z < 0.56) {
			screenPos.z = screenPos.z * rcp(MC_HAND_DEPTH) + (0.5 - 0.5 / MC_HAND_DEPTH);
		}

		vec3 viewPos = ScreenToViewPos(screenPos);

		#if defined LOD_MOD
			bool lodMask = screenPos.z > 1.0 - EPS;
			if (lodMask) {
				screenPos.z = loadDepth0Lod(texelPos);
				viewPos = ScreenToViewPosLod(screenPos);
			}
		#endif

		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
		vec3 worldDir = normalize(worldPos);
		worldPos += gbufferModelViewInverse[3].xyz;

		vec3 worldNormal = FetchSurfaceNormal(texelPos);

		vec2 lightmap = Unpack2x8U(loadMaterialPack(texelPos).x);

		float dither = BlueNoise(texelPos, frameCounter);
		specularOut = CalculateSpecularReflections(material, worldNormal, screenPos, worldDir, viewPos, lightmap.y, dither);
	}
}
