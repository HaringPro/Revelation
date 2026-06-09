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

/* RENDERTARGETS: 6 */
out vec4 albedoOut;

//======// Input //===============================================================================//

flat in vec4 vertColor;
in vec2 texCoord;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

uniform vec2 scaledViewSize;

//======// Main //================================================================================//
void main() {
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        if (any(greaterThanEqual(gl_FragCoord.xy, scaledViewSize))) {
            discard;
        }
    #endif

	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) discard;

	albedoOut = albedo;
}
