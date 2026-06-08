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

/* RENDERTARGETS: 7,8 */
layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;

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

#if defined MC_NORMAL_MAP
	uniform sampler2D normals;
#endif

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) discard;

	materialOut.x = Pack2x8U(lightmap);
	#if GBUFFER_PARTICLES_TRANSLUCENT
		materialOut.y = 500u;
	#else
		materialOut.y = 2u;
	#endif

	materialOut.z = Pack2x8U(albedo.xy);
	materialOut.w = Pack2x8U(albedo.zw);

	normalOut.xy = unpackSnorm2x16(normalPack);
	vec3 geoNormal = OctDecodeSnorm(normalOut.xy);

	#ifdef MC_NORMAL_MAP
		// Construct TBN matrix
		vec3 tangent = UnpackSnorm3x10(tangentPack);
		vec3 bitangent = cross(tangent, geoNormal);
        bitangent *= uintBitsToFloat(bitfieldExtract(tangentPack, 30, 2));
		mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);

		vec3 normalTex = texture(normals, texCoord).rgb;
		DecodeNormalTex(normalTex);
		normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
	#else
		normalOut.zw = normalOut.xy;
	#endif
}
