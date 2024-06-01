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

#define TORCHLIGHT_COLOR_TEMPERATURE 3000 // Color temperature of torch light in Kelvin. [1000 1500 2000 2300 2500 3000 3400 3500 4000 4500 5000 5500 6000]

//======// Output //==============================================================================//

out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out vec3 sunIlluminance;
flat out vec3 moonIlluminance;

flat out vec3 blocklightColor;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler3D colortex1;

uniform int moonPhase;

uniform float eyeAltitude;
uniform float nightVision;
uniform float wetness;

uniform vec3 worldSunVector;

//======// Function //============================================================================//

#include "/lib/atmospherics/Common.inc"

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	vec3 camera = vec3(0.0, planetRadius + eyeAltitude, 0.0);
	skyIlluminance = GetSunAndSkyIrradiance(atmosphereModel, camera, worldSunVector, sunIlluminance, moonIlluminance);
	directIlluminance = sunIlluminance + moonIlluminance;

	blocklightColor = blackbody(float(TORCHLIGHT_COLOR_TEMPERATURE));
}