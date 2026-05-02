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
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = diagonal4(gl_ProjectionMatrix) * viewPos.xyzz + gl_ProjectionMatrix[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaJitter * gl_Position.w;
	#endif
}
