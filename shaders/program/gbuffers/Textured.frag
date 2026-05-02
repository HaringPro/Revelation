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

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
/* RENDERTARGETS: 6,7,8,12 */
layout (location = 3) out float parallaxShadowOut;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined MC_SPECULAR_MAP
	uniform sampler2D specular;
#endif

//======// Input //===============================================================================//

in vec3 worldPos;

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedoOut = vec4(albedo.rgb, 1.0);

	materialOut.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	materialOut.y = lightmap.x > 0.999 ? 20u : 40u;

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = texture(specular, texCoord);
		materialOut.z = Packup2x8U(specularTex.xy);
		materialOut.w = Packup2x8U(specularTex.zw);
	#else
		materialOut.zw = uvec2(0);
	#endif

	vec3 geoNormal = normalize(cross(dFdx(worldPos), dFdy(worldPos)));

	normalOut.xy = OctEncodeSnorm(geoNormal);
	normalOut.zw = normalOut.xy;

	#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
		parallaxShadowOut = 0.0;
	#endif
}
