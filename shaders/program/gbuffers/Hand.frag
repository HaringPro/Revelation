/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE && GBUFFERS_HAND
/* RENDERTARGETS: 6,7,8,12 */
layout (location = 3) out float parallaxShadowOut;
#endif

//======// Input //===============================================================================//

flat in uint normalPack;
#if defined MC_NORMAL_MAP
flat in uint tangentPack;
#endif

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;

//======// Uniform //=============================================================================//

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) discard;

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedoOut = albedo;

	materialOut.x = Pack2x8U(lightmap);
	#if GBUFFERS_PARTICLES_TRANSLUCENT
		materialOut.y = 500u;
	#elif GBUFFERS_HAND_WATER
		materialOut.y = 2u;
	#else
	    materialOut.y = 1u;
	#endif

	#if defined MC_SPECULAR_MAP && GBUFFERS_HAND
		vec4 specularTex = texture(specular, texCoord);
		materialOut.z = Pack2x8U(specularTex.xy);
		materialOut.w = Pack2x8U(specularTex.zw);
	#else
		materialOut.zw = uvec2(0);
	#endif

	normalOut.xy = unpackSnorm2x16(normalPack);
	vec3 geoNormal = OctDecodeSnorm(normalOut.xy);

	#if defined MC_NORMAL_MAP && !GBUFFERS_PARTICLES_TRANSLUCENT
		// Construct TBN matrix
		vec3 tangent = UnpackSnorm3x10(tangentPack);
		vec3 bitangent = cross(tangent, geoNormal);
        bitangent *= 1.0 - 2.0 * float(bitfieldExtract(tangentPack, 30, 1));
		mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);

		vec3 normalTex = texture(normals, texCoord).rgb;
		DecodeNormalTex(normalTex);
		normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
	#else
		normalOut.zw = normalOut.xy;
	#endif

	#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE && GBUFFERS_HAND
		parallaxShadowOut = 0.0;
	#endif
}
