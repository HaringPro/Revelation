
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,3,4 */
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out vec4 gbufferOut0;
layout(location = 2) out vec2 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Input //===============================================================================//

in vec3 flatNormal;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * tint;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedoOut = albedo;

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut1.x = packUnorm2x8(encodeUnitVector(flatNormal));
	gbufferOut1.y = gbufferOut1.x;
}
