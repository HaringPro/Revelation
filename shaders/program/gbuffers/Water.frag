
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,3 */
layout(location = 0) out vec4 sceneOut;
layout(location = 1) out vec4 gbufferOut0;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

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

	if (materialID == 3u) sceneOut = vec4(0.0); // water
	else sceneOut = vec4(sqr(albedo.rgb), pow(albedo.a, 0.3));

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;
}
