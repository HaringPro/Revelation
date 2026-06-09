#version 460 compatibility

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

out vec3 vertColor;
out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	transformVertexPosition(gl_Position, viewPos, taaJitter);
}
