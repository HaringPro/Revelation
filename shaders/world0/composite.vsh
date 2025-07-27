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

flat out mat2x3 fogExtinctionCoeff;
flat out mat2x3 fogScatteringCoeff;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform float wetness;
uniform float biomeSandstorm;
uniform float biomeGreenVapor;

uniform float timeNoon;
uniform float timeMidnight;

uniform vec3 fogMieExtinction;
uniform vec3 fogMieScattering;
uniform vec3 fogRayleighExtinction;
uniform vec3 fogRayleighScattering;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);

	float mieDensityMult = VF_MIE_DENSITY * (1.0 + wetness * VF_MIE_DENSITY_RAIN_MULT);

	fogExtinctionCoeff = mat2x3(
		fogMieExtinction * mieDensityMult,
		fogRayleighExtinction * VF_RAYLEIGH_DENSITY
	);

	fogScatteringCoeff = mat2x3(
		fogMieScattering * mieDensityMult,
		fogRayleighScattering * VF_RAYLEIGH_DENSITY
	);
}