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
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec4 materialOut;
layout(location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW
/* RENDERTARGETS: 6,7,8,12 */
layout(location = 3) out float parallaxOffsetOut;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

// uniform vec3 skyColor;

uniform vec4 entityColor;

uniform vec2 scaledViewSize;

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

//======// Main //================================================================================//
void main() {
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        if (any(greaterThanEqual(gl_FragCoord.xy, scaledViewSize))) {
            discard;
        }
    #endif

    vec2 deltaUv1 = dFdx(texCoord);
    vec2 deltaUv2 = dFdy(texCoord);

	vec4 albedo = textureGrad(tex, texCoord, deltaUv1, deltaUv2) * vertColor;

	// if (materialID == 2000u) albedo = vec4(skyColor, 1.0);
	if (materialID == 2000u) albedo.rgb = vec3(0.7, 0.675, 1.0);

	if (albedo.a < 0.1) discard;

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	albedoOut = albedo;

	materialOut.x = Pack2x8U(lightmap);
	#if GBUFFERS_SPIDEREYES
		materialOut.y = 20u;
	#else
		materialOut.y = materialID;
	#endif

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = textureGrad(specular, texCoord, deltaUv1, deltaUv2);
		materialOut.z = Pack2x8U(specularTex.xy);
		materialOut.w = Pack2x8U(specularTex.zw);
	#else
		materialOut.zw = uvec2(0);
	#endif

	normalOut.xy = OctEncodeSnorm(geoNormal);

	#if defined MC_NORMAL_MAP
		vec3 normalTex = textureGrad(normals, texCoord, deltaUv1, deltaUv2).rgb;
		DecodeNormalTex(normalTex);
		normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
	#else
		normalOut.zw = normalOut.xy;
	#endif

	#if defined PARALLAX && defined PARALLAX_SHADOW
		parallaxOffsetOut = 0.0;
	#endif
}
