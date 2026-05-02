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

flat out vec4 vertColor;
out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = project(gl_ProjectionMatrix, viewPos);

	transformVertexPosition(
        gl_Position,
        taaJitter,
        MC_RENDER_SCALE_FACTOR
    );

	vertColor = gl_Color;
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
