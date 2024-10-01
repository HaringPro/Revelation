
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec3 albedoOut;
layout (location = 1) out vec4 gbufferOut0;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec2 gbufferOut1;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

//======// Input //===============================================================================//

in vec3 flatNormal;

in vec4 tint;
in vec2 texCoord;

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * tint;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedoOut = albedo.rgb;

	gbufferOut0.y = 20.0 * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(flatNormal));
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
        if (albedo.a > 0.999) {
            vec4 specularTex = texture(specular, texCoord);

            gbufferOut1.x = packUnorm2x8(specularTex.rg);
            gbufferOut1.y = packUnorm2x8(specularTex.ba);
        }
	#endif
}