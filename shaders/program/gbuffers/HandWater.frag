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

in vec3 worldPos;

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

	if (albedo.a < 0.1) { discard; return; }

	materialOut.x = Pack2x8U(lightmap);
	#if GBUFFER_PARTICLES_TRANSLUCENT
		materialOut.y = 500u;
	#else
		materialOut.y = 2u;
	#endif

	materialOut.z = Pack2x8U(albedo.xy);
	materialOut.w = Pack2x8U(albedo.zw);

	vec3 deltaPos1 = dFdx(worldPos);
	vec3 deltaPos2 = dFdy(worldPos);

	vec3 geoNormal = normalize(cross(deltaPos1, deltaPos2));
	normalOut.xy = OctEncodeSnorm(geoNormal);

	#ifdef MC_NORMAL_MAP
		// Construct TBN matrix
		vec3 deltaPos1Perp = cross(geoNormal, deltaPos1);
		vec3 deltaPos2Perp = cross(deltaPos2, geoNormal);

		vec2 deltaUv1 = dFdx(texCoord);
		vec2 deltaUv2 = dFdy(texCoord);

		vec3 tangent   = normalize(deltaPos2Perp * deltaUv1.x + deltaPos1Perp * deltaUv2.x);
		vec3 bitangent = normalize(deltaPos2Perp * deltaUv1.y + deltaPos1Perp * deltaUv2.y);

		float invmax = inversesqrt(max(sdot(tangent), sdot(bitangent)));
		mat3 tbnMatrix = mat3(tangent * invmax, bitangent * invmax, geoNormal);

		vec3 normalTex = texture(normals, texCoord).rgb;
		DecodeNormalTex(normalTex);
		normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
	#else
		normalOut.zw = normalOut.xy;
	#endif
}
