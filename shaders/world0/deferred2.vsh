#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

//======// Attribute //===========================================================================//

in vec3 vaPosition;

//======// Uniform //=============================================================================//

uniform sampler2D colortex4; // Global illuminances

//======// Main //================================================================================//
void main() {
	#ifdef CLOUD_CBR_ENABLED
    	gl_Position = vec4(vaPosition * (2.0 / CLOUD_CBR_SCALE) - 1.0, 1.0);
	#else
    	gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	#endif

	directIlluminance = loadDirectIllum();
	skyIlluminance = loadSkyIllum();
}