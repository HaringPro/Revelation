#version 450 compatibility

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 albedoOut;

//======// Input //===============================================================================//

in vec3 tint;
in vec2 texCoord;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord);

	if (albedo.a < 0.1) { discard; return; }

	albedoOut = albedo.rgb * tint;
}