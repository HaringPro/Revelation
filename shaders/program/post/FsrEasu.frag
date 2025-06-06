/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: FSR EASU stage

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 15 */
out vec3 easuOut;

//======// Uniform //=============================================================================//

uniform sampler2D colortex0; // LDR scene image
uniform sampler2D colortex15; // FSR EASU output

uniform vec2 viewSize;

//======// Function //============================================================================//

#define FsrEasuCF(coord) textureLod(colortex0, coord, 0.0).rgb

#include "/lib/post/FSR.glsl"

//======// Main //================================================================================//
void main() {
    vec4 con0, con1, con2, con3;

    FsrEasuCon(con0, con1, con2, con3, viewSize, viewSize, ceil(viewSize / MC_RENDER_QUALITY));
    FsrEasuF(easuOut, gl_FragCoord.xy, con0, con1, con2, con3);
}