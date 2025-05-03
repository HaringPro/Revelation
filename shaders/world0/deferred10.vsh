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
	flat out vec3[4] skySH;
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
		skySH = vec3[4](0.0);
		const uvec2 samples = uvec2(8u, 4u);
		const vec2 rSamples = 1.0 / vec2(samples);

		for (uint y = 0u; y < samples.y; ++y) {
			float latitude = float(y) * (PI * rSamples.y);
			vec2 latitudeSincos = sincos(latitude);
			for (uint x = 0u; x < samples.x; ++x) {
				float longitude = float(x) * (TAU * rSamples.x);
				vec3 direction = vec3(abs(latitudeSincos.x), latitudeSincos.y * sincos(longitude)).zxy;

				vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(direction) + vec2(0.0, 0.5)).rgb;
				vec3[4] shCoeff = ToSphericalHarmonics(skyRadiance, direction);
				for (uint band = 0u; band < 4u; ++band) {
					skySH[band] += shCoeff[band];
				}
			}
		}

		const float norm = rSamples.x * rSamples.y;
		for (uint band = 0u; band < 4u; ++band) {
			skySH[band] *= norm;
		}
	#endif
}