#version 450 compatibility

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

out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out mat2x3[2] fogCoeff;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex5;

uniform float wetness;
uniform float wetnessCustom;
uniform float lightningFlashing;
uniform float timeNoon;
uniform float timeMidnight;
uniform float timeSunrise;
uniform float timeSunset;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

	mat2x3 fogExtinctionCoeff = mat2x3(
		vec3(FOG_MIE_DENSITY),
		vec3(0.32, 0.45, 1.0) * FOG_RAYLEIGH_DENSITY
	);

	#ifdef TIME_FADE
		float fadeFactor = max(wetness, sqr(1.0 - timeNoon * 0.85));
		fogExtinctionCoeff[0] *= fadeFactor;
	#endif

	mat2x3 fogScatteringCoeff = mat2x3(
		fogExtinctionCoeff[0] * (0.9 - wetness * 0.5),
		fogExtinctionCoeff[1]
	);

	fogExtinctionCoeff[0] *= 1.0 + wetness * FOG_MIE_DENSITY_RAIN_MULTIPLIER;

	fogCoeff[0] = fogExtinctionCoeff;
	fogCoeff[1] = fogScatteringCoeff;
}