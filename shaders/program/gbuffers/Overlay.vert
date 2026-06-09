/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#define RENDER_SCALE_VERTEX
#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out vec4 vertColor;
out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
    transformVertexPosition(gl_Position, viewPos, taaJitter);

	vertColor = gl_Color;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);
}
