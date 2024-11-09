
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 gbufferOut0;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec2 gbufferOut1;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

// uniform vec3 skyColor;

uniform vec4 entityColor;

//======// Input //===============================================================================//

#if defined NORMAL_MAPPING
	in mat3 tbnMatrix; // Not use flat because of the Physics mod snow
	#define flatNormal tbnMatrix[2]
#else
	in vec3 flatNormal;
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

	// if (materialID == 60u) albedo = vec4(skyColor, 1.0);
	if (materialID == 60u) albedo = vec4(0.7, 0.675, 1.0, 1.0);

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	albedoOut = albedo;

	gbufferOut0.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = materialID;

	gbufferOut0.z = Packup2x8U(encodeUnitVector(flatNormal));
	#if defined NORMAL_MAPPING
        vec3 normalTex = texture(normals, texCoord).rgb;
        DecodeNormalTex(normalTex);
		gbufferOut0.w = Packup2x8U(encodeUnitVector(tbnMatrix * normalTex));
	#endif
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 specularTex = texture(specular, texCoord);

		gbufferOut1.x = Packup2x8(specularTex.rg);
		gbufferOut1.y = Packup2x8(specularTex.ba);
	#endif
}