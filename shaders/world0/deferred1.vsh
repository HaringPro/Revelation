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

uniform sampler2D colortex5;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * (2.0 / CLOUD_TEMPORAL_UPSCALING) - 1.0, 1.0);

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;
}