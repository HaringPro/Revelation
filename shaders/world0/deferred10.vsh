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

#define SH_SLICES 5 // [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15]

//======// Output //==============================================================================//

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out mat4x3 skySH;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex5;

uniform int moonPhase;

uniform float nightVision;
uniform float eyeAltitude;

//======// Function //============================================================================//

#include "/lib/atmospherics/Global.glsl"

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

	skySH = mat4x3(0.0);
	const float rSlices = 1.0 / float(SH_SLICES);

	for (uint h = 0u; h < SH_SLICES; ++h) {
		float latitude = float(h) * PI * rSlices;
		vec2 latitudeSincos = sincos(latitude);
		for (uint v = 0u; v < SH_SLICES; ++v) {
			float longitude = float(v) * TAU * rSlices;
			vec3 direction = vec3(latitudeSincos.x, latitudeSincos.y * sincos(longitude)).zxy;

			vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(direction) + vec2(0.0, 0.5)).rgb;
			skySH += ToSphericalHarmonics(skyRadiance, direction);
		}
	}

	skySH *= rSlices * rSlices;
}