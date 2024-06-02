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

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,10 */
layout(location = 0) out vec3 skyViewOut;
layout(location = 1) out vec3 transmittanceOut;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in vec3 sunIlluminance;
flat in vec3 moonIlluminance;

//======// Attribute //===========================================================================//

//======// Uniform //=============================================================================//

uniform sampler3D colortex1;

uniform float nightVision;
uniform float wetness;
uniform float eyeAltitude;

uniform int moonPhase;

uniform vec3 worldSunVector;

//======// Function //============================================================================//

#include "/lib/atmospherics/Common.inc"

//================================================================================================//

//======// Main //================================================================================//
void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	if (texel.x == skyCaptureRes.x) {
		switch (texel.y) {
            case 0:
                skyViewOut = directIlluminance;
                break;

            case 1:
                skyViewOut = skyIlluminance;
                break;

            case 2:
                skyViewOut = sunIlluminance;
                break;

            case 3:
                skyViewOut = moonIlluminance;
                break;
		}
	} else if (texel.y < skyCaptureRes.y) {
		// Raw sky map

		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(atmosphereModel, worldDir, worldSunVector, transmittanceOut) * 6.0;
	} else {
		// Sky map with clouds

		vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
		skyViewOut = GetSkyRadiance(atmosphereModel, worldDir, worldSunVector, transmittanceOut) * 6.0;
	}
}
