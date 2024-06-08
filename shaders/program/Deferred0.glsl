/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

#if defined VERTEX_SHADER

//======// Output //==============================================================================//

out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out vec3 sunIlluminance;
flat out vec3 moonIlluminance;

flat out float exposure;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex1; // Previous scene color
uniform sampler2D colortex2;

uniform sampler3D colortex3; // Combined Atmospheric LUT

uniform int moonPhase;

uniform float frameTime;

uniform float eyeAltitude;
uniform float nightVision;
uniform float wetness;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;

uniform vec3 worldSunVector;

//======// Function //============================================================================//

#include "/lib/atmospherics/Global.inc"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

float CalculateWeightedLuminance() {
    const float tileSize = exp2(-float(AUTO_EXPOSURE_LOD));

	ivec2 tileSteps = ivec2(viewSize * tileSize);
    vec2 rTileSteps = 1.0 / vec2(tileSteps);

    float total = 0.0;
    float sumWeight = 0.0;

    const float minEV = -16.0;
    const float maxEV = 12.0;

	for (uint x = 0u; x < tileSteps.x; ++x) {
        for (uint y = 0u; y < tileSteps.y; ++y) {
            vec2 uv = (vec2(x, y) + 0.5) * rTileSteps;
            float luminance = GetLuminance(texture(colortex1, uv, AUTO_EXPOSURE_LOD).rgb);

            float weight = 1.0 - curve(length(uv * 2.0 - 1.0));

            total += clamp(log2(luminance), minEV, maxEV) * weight;
            sumWeight += weight;
        }
	}

    total /= sumWeight;

	return exp2(total * -0.7);
}

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	vec3 camera = vec3(0.0, viewerHeight, 0.0);
	skyIlluminance = GetSunAndSkyIrradiance(atmosphereModel, camera, worldSunVector, sunIlluminance, moonIlluminance);
	directIlluminance = sunIlluminance + moonIlluminance;

 	#ifdef AUTO_EXPOSURE
		exposure = CalculateWeightedLuminance();

        float targetExposure = exp2(AUTO_EXPOSURE_BIAS) * 0.45 * exposure;
        // float targetExposure = exp2(AUTO_EXPOSURE_BIAS) / (0.8 - 0.002 * fastExp(-exposure * rcp(K * 1e-2 * (0.8 - 0.002))));

        float prevExposure = texelFetch(colortex2, ivec2(skyCaptureRes.x, 4), 0).x;

        float fadedSpeed = targetExposure < prevExposure ? 2.0 : 1.0;
        exposure = mix(targetExposure, prevExposure, fastExp(-fadedSpeed * frameTime * EXPOSURE_SPEED));
	#else
		exposure = exp2(-MANUAL_EXPOSURE_VALUE);
	#endif
}

#else

//======// Output //==============================================================================//

/*
const bool colortex1MipmapEnabled = true;
*/

/* RENDERTARGETS: 2,10 */
layout(location = 0) out vec3 skyViewOut;
layout(location = 1) out vec3 transmittanceOut;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in vec3 sunIlluminance;
flat in vec3 moonIlluminance;

flat in float exposure;

//======// Attribute //===========================================================================//

//======// Uniform //=============================================================================//

uniform sampler3D colortex3; // Combined Atmospheric LUT

uniform float nightVision;
uniform float wetness;
uniform float eyeAltitude;

uniform int moonPhase;

uniform vec3 worldSunVector;

//======// Function //============================================================================//

#include "/lib/atmospherics/Global.inc"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

//================================================================================================//

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	if (screenTexel.x == skyCaptureRes.x) {
		switch (screenTexel.y) {
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

            case 4:
                skyViewOut.x = exposure;
                break;
		}
	} else if (screenTexel.y < skyCaptureRes.y) {
		// Raw sky map

		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(atmosphereModel, worldDir, worldSunVector, transmittanceOut) * 20.0;
	} else {
		// Sky map with clouds

		// vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
		// skyViewOut = GetSkyRadiance(atmosphereModel, worldDir, worldSunVector, transmittanceOut) * 20.0;
	}
}

#endif