
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec2 gbufferOut0;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

uniform vec4 entityColor;

//======// Input //===============================================================================//

in vec4 vertColor;
in vec2 texCoord;

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
	albedoOut = vec4(albedo.rgb, 1.0);

	gbufferOut0.y = 20u;
}