#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

#define BLOCKLIGHT_TEMPERATURE 3000 // [1000 1500 2000 2300 2500 3000 3400 3500 4000 4500 5000 5500 6000]

//======// Output //==============================================================================//

out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out vec3 blocklightColor;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex2;

//======// Function //============================================================================//

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	directIlluminance = texelFetch(colortex2, ivec2(skyCaptureRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex2, ivec2(skyCaptureRes.x, 1), 0).rgb;

	blocklightColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
}