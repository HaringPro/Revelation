/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec2 materialOut;

//======// Input //===============================================================================//

flat in vec4 vertColor;
in vec2 lightmap;

//======// Main //================================================================================//
void main() {
	if (vertColor.a < 0.1) discard;

	albedoOut = vec4(vertColor.rgb, 1.0);

	materialOut.x = Pack2x8U(lightmap);
	materialOut.y = lightmap.x > 0.999 ? 20u : 1u;
}
