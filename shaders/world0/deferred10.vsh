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

#ifndef SSPT_ENABLED
	flat out mat4x3 skySH;
#endif

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex4; // Global illuminances
uniform sampler2D colortex5; // Sky-View LUT

uniform int moonPhase;

uniform float nightVision;
uniform float eyeAltitude;

//======// Function //============================================================================//

#include "/lib/atmosphere/Global.glsl"

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);

	directIlluminance = loadDirectIllum();
	skyIlluminance = loadSkyIllum();

	#ifndef SSPT_ENABLED
		skySH = mat4x3(0.0);
		const uint slices = 5u;
		const float rSlices = 1.0 / float(slices);

		for (uint y = 0u; y < slices; ++y) {
			float latitude = float(y) * (PI * rSlices);
			vec2 latitudeSincos = sincos(latitude);
			for (uint x = 0u; x < slices; ++x) {
				float longitude = float(x) * (TAU * rSlices);
				vec3 direction = vec3(latitudeSincos.x, latitudeSincos.y * sincos(longitude)).zxy;

				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(direction) + vec2(0.0, 0.5)).rgb;
				skySH += ToSphericalHarmonics(skyRadiance, direction);
			}
		}

		skySH *= rSlices * rSlices;
	#endif
}