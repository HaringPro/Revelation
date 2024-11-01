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

flat out mat2x3 fogExtinctionCoeff;
flat out mat2x3 fogScatteringCoeff;

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

uniform vec3 fmExtinction;
uniform vec3 fmScattering;
uniform vec3 frExtinction;
uniform vec3 frScattering;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

	fogExtinctionCoeff = mat2x3(
		fmExtinction * VF_MIE_DENSITY,
		frExtinction * VF_RAYLEIGH_DENSITY
	);

	fogScatteringCoeff = mat2x3(
		fmScattering * VF_MIE_DENSITY,
		frScattering * VF_RAYLEIGH_DENSITY
	);

	fogExtinctionCoeff[0] *= 1.0 + wetness * VF_MIE_DENSITY_RAIN_MULTIPLIER;
}