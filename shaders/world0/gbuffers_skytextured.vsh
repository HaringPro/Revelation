#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/settings.glsl"

//======// Output //==============================================================================//

out vec3 tint;
out vec2 texCoord;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	tint = vaColor.rgb;
	texCoord = vaUV0;

	gl_Position = projectionMatrix * modelViewMatrix * vec4(vaPosition, 1.0);

    #ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
    #endif
}