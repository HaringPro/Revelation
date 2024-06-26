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

flat out mat4x3 skySH;

flat out vec3 blocklightColor;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex5;

uniform int moonPhase;

uniform float nightVision;
uniform float eyeAltitude;

//======// Function //============================================================================//

#include "/lib/atmospherics/Global.inc"

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

	skySH = mat4x3(0.0);

	for (uint h = 0u; h < 5u; ++h) {
		float latitude = float(h) * PI * 0.2;
		vec2 latitudeSincos = sincos(latitude);
		for (uint v = 0u; v < 5u; ++v) {
			float longitude = float(v) * PI * 0.4;
			vec3 direction = vec3(latitudeSincos.x, latitudeSincos.y * sincos(longitude)).zxy;

			vec3 skyRadiance = texture(colortex5, FromSkyViewLutParams(direction)).rgb;
			skySH += ToSphericalHarmonics(skyRadiance, direction);
		}
	}

	skySH *= 1.0 / 25.0;

	blocklightColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
}