/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"
#include "/lib/surface/Emission.glsl"

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

uniform vec4 entityColor;

uniform float alphaTestRef;

uniform vec2 scaledViewSize;
uniform vec2 renderScale;

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
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        deltaUv1 *= renderScale.x;
        deltaUv2 *= renderScale.y;
    #endif

	#if GBUFFERS_LIGHTNING
       vec4 albedo = vec4(0.7, 0.675, 1.0, texture(tex, texCoord).a);
    #else
        vec4 albedoTex = textureGrad(tex, texCoord, deltaUv1, deltaUv2);
        vec4 albedo = albedoTex * vertColor;
        if (albedo.a < alphaTestRef) discard;
    #endif

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	albedoOut = albedo;

	materialOut.x = Pack2x8U(lightmap);
	#if GBUFFERS_SPIDEREYES
		materialOut.y = WriteBuiltinMaterial(MAT_GLOW, albedo.rgb, vec3(0.0));
	#elif GBUFFERS_LIGHTNING
		materialOut.y = WriteBuiltinMaterial(MAT_LIGHTNING, albedo.rgb, vec3(0.0));
	#else
		uint id = materialID;
		if (id == MAT_GUARDIAN) {
			float darkest = minOf(albedoTex.rgb);
			if (darkest <= 0.78 || maxOf(albedoTex.rgb) - darkest >= 0.016) id = MAT_SOLID;
		}
		vec3 emissionColor = albedo.rgb;
		if (id == MAT_GLOW_SQUID) emissionColor *= lightmap.x;
		materialOut.y = WriteBuiltinMaterial(id, emissionColor, vec3(0.0));
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
