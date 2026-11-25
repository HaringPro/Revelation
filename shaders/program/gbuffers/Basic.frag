/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"
#include "/lib/surface/Emission.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec2 materialOut;

//======// Input //===============================================================================//

flat in vec4 vertColor;
in vec2 lightmap;

//======// Uniform //=============================================================================//

uniform float alphaTestRef;

uniform vec2 scaledViewSize;

//======// Main //================================================================================//
void main() {
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        if (any(greaterThanEqual(gl_FragCoord.xy, scaledViewSize))) {
            discard;
        }
    #endif

	if (vertColor.a < alphaTestRef) discard;

	albedoOut = vec4(vertColor.rgb, 1.0);

	materialOut.x = Pack2x8U(lightmap);
	materialOut.y = lightmap.x > 0.999 ? WriteBuiltinMaterial(MAT_GLOW, vertColor.rgb, vec3(0.0)) : MAT_SOLID;
}
