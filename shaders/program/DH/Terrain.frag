
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec3 gbufferOut0;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec2 gbufferOut1;
#endif

//======// Input //===============================================================================//

flat in vec3 flatNormal;
in vec3 worldPos;

in vec3 vertColor;
in vec2 lightmap;
flat in uint materialID;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform vec3 cameraPosition;
uniform float far;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void main() {
    if (length(worldPos) < 0.75 * far) { discard; return; }

	albedoOut = vec4(vertColor, 1.0);
	/* Terrain noises */ {
		const float res = 8.0;
		const float strength = 0.25;

		mat3 tbnMatrix = ConstructTBN(flatNormal);

		vec2 coord = ((worldPos + cameraPosition) * tbnMatrix).xy * (res / 256.0);
		float noise = texture(noisetex, coord).x * 2.0;

		albedoOut.rgb = saturate(albedoOut.rgb * mix(1.0, noise, strength));
	}

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	gbufferOut0.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = materialID;

	gbufferOut0.z = Packup2x8U(OctEncodeUnorm(flatNormal));
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		gbufferOut1 = vec2(0.0);
	#endif
}