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

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined MC_NORMAL_MAP
	uniform sampler2D normals;
#endif

#if defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

// uniform vec3 skyColor;

uniform vec4 entityColor;

//======// Input //===============================================================================//

#if defined MC_NORMAL_MAP
	in mat3 tbnMatrix;
	#define geoNormal tbnMatrix[2]
#else
	in vec3 geoNormal;
#endif

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	// if (materialID == 2000u) albedo = vec4(skyColor, 1.0);
	if (materialID == 2000u) albedo.rgb = vec3(0.7, 0.675, 1.0);

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	albedoOut = albedo;

	materialOut.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	materialOut.y = materialID;

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = texture(specular, texCoord);
		materialOut.z = Packup2x8U(specularTex.xy);
		materialOut.w = Packup2x8U(specularTex.zw);
	#else
		materialOut.zw = uvec2(0);
	#endif

	normalOut.xy = OctEncodeUnorm(geoNormal);

	#if defined MC_NORMAL_MAP
        vec3 normalTex = texture(normals, texCoord).rgb;
        DecodeNormalTex(normalTex);
		normalOut.zw = OctEncodeUnorm(tbnMatrix * normalTex);
	#else
		normalOut.zw = normalOut.xy;
	#endif
}