
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec2 gbufferOut0;

//======// Input //===============================================================================//

flat in vec4 vertColor;
in vec2 lightmap;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void main() {
	if (vertColor.a < 0.1) { discard; return; }

	albedoOut = vec4(vertColor.rgb, 1.0);

	uint materialID = lightmap.x > 0.999 ? 20u : 1u;
	gbufferOut0.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = materialID;
}