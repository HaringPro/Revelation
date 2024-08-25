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

flat out mat2x3[2] fogCoeff;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex5;

uniform float wetness;
uniform float biomeSandstorm;
uniform float biomeGreenVapor;

uniform float timeNoon;
uniform float timeMidnight;

uniform vec3 fogMieExtinction;
uniform vec3 fogMieScattering;
uniform vec3 fogRayleighCoeff;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

	mat2x3 fogExtinctionCoeff = mat2x3(
		fogMieExtinction * FOG_MIE_DENSITY,
		fogRayleighCoeff * FOG_RAYLEIGH_DENSITY
	);

	mat2x3 fogScatteringCoeff = mat2x3(
		fogMieScattering * FOG_MIE_DENSITY,
		fogExtinctionCoeff[1]
	);

	fogExtinctionCoeff[0] *= 1.0 + wetness * FOG_MIE_DENSITY_RAIN_MULTIPLIER;

	fogCoeff[0] = fogExtinctionCoeff;
	fogCoeff[1] = fogScatteringCoeff;
}