
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out vec4 gbufferOut0;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec2 gbufferOut1;
#endif

//======// Input //===============================================================================//

#if defined NORMAL_MAPPING
	flat in mat3 tbnMatrix;
	#define flatNormal tbnMatrix[2]
#else
	flat in vec3 flatNormal;
#endif

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

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

	albedoOut = albedo;

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(flatNormal));
	#if defined NORMAL_MAPPING
        vec3 normalTex = texture(normals, texCoord).rgb;
        DecodeNormalTex(normalTex);
		gbufferOut0.w = packUnorm2x8(encodeUnitVector(tbnMatrix * normalTex));
	#endif
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 specularTex = texture(specular, texCoord);

		gbufferOut1.x = packUnorm2x8(specularTex.rg);
		gbufferOut1.y = packUnorm2x8(specularTex.ba);
	#endif
}