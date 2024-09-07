/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass:
    - Vertex Shader:   Compute illuminances and exposure
    - Fragment Shader: Compute Sky-View LUT and Transmittance-View LUT, store illuminances and exposure

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#if defined VERTEX_SHADER

//======// Output //==============================================================================//

noperspective out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

flat out vec3 sunIlluminance;
flat out vec3 moonIlluminance;

flat out float exposure;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler3D colortex0; // Combined atmospheric LUT
uniform sampler2D colortex1; // Scene history
uniform sampler2D colortex5; // Previous exposure

uniform int moonPhase;

uniform float frameTime;

uniform float eyeAltitude;
uniform float nightVision;
uniform float wetness;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;

uniform vec3 worldSunVector;

//======// Function //============================================================================//

#include "/lib/atmospherics/Global.glsl"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

#define HISTOGRAM_AE // Enables auto exposure histogram

#define HISTOGRAM_BIN_COUNT 32 // [8 16 32 64 128 256 512 1024]
#define HISTOGRAM_MIN_EV -20.0 // [-24.0 -20.0 -16.0 -12.0 -8.0 -4.0 -2.0 -1.0 0.0 1.0 2.0 4.0 8.0 12.0 16.0 20.0 24.0]
#define HISTOGRAM_LOWER_BOUND 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
#define HISTOGRAM_UPPER_BOUND 0.9 // [0.5 0.6 0.7 0.8 0.9 1.0]

float CalculateAutoExposure() {
    const float tileSize = exp2(-float(AUTO_EXPOSURE_LOD));

	ivec2 tileSteps = ivec2(viewSize * tileSize);
    vec2 pixelSize = 1.0 / vec2(tileSteps);

    #ifdef HISTOGRAM_AE
        float lumBucket[HISTOGRAM_BIN_COUNT];

        // Initialize luminance bucket
        for (uint i = 0u; i < HISTOGRAM_BIN_COUNT; ++i) lumBucket[i] = 0.0;
    #endif

    float sum = 0.0;
    float sumWeight = 0.0;

    // Compute luminance for each tile
	for (uint x = 0u; x < tileSteps.x; ++x) {
        for (uint y = 0u; y < tileSteps.y; ++y) {
            vec2 uv = (vec2(x, y) + 0.5) * pixelSize;
            float luminance = GetLuminance(textureLod(colortex1, uv, AUTO_EXPOSURE_LOD).rgb);

            float weight = exp2(-0.2 * dotSelf(uv * 2.0 - 1.0));

            #ifdef HISTOGRAM_AE
                // Build luminance bucket
                lumBucket[clamp(int(log2(luminance) - HISTOGRAM_MIN_EV), 0, HISTOGRAM_BIN_COUNT - 1)] += weight;
            #else
                sum += log2(luminance) * weight;
            #endif
            sumWeight += weight;
        }
	}

    #ifdef HISTOGRAM_AE
        float sumWeightInv = 1.0 / sumWeight;

        float prefix = 0.0;
        vec2 lum = vec2(0.0), weight = vec2(0.0);
        uint i = 0u;
        for (; i < HISTOGRAM_BIN_COUNT; ++i) {
            prefix += lumBucket[i] * sumWeightInv;
            if (prefix > HISTOGRAM_LOWER_BOUND) {
                weight.x = prefix - HISTOGRAM_LOWER_BOUND;
                lum.x = float(i) * weight.x;
                break;
            }
        }
        for (; i < HISTOGRAM_BIN_COUNT; ++i) {
            prefix += lumBucket[i] * sumWeightInv;
            if (prefix > HISTOGRAM_UPPER_BOUND) {
                weight.y = prefix - HISTOGRAM_UPPER_BOUND;
                lum.y = float(i) * weight.y;
                break;
            }
        }

        sum = (lum.x + lum.y) / (weight.x + weight.y) + HISTOGRAM_MIN_EV;
    #else
        sum /= sumWeight;
    #endif

	return exp2(sum);
}

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	vec3 camera = vec3(0.0, planetRadius + eyeAltitude, 0.0);
	skyIlluminance = GetSunAndSkyIrradiance(camera, worldSunVector, sunIlluminance, moonIlluminance);
	directIlluminance = sunIlluminance + moonIlluminance;

 	#ifdef AUTO_EXPOSURE
		exposure = CalculateAutoExposure();

        const float K = 12.5;
        const float cal = K / ISO;
        const float m = 3.5, r = m - 0.01;
        float targetExposure = exp2(AUTO_EV_BIAS) / (m - r * fastExp(-exposure * rcp(cal * r)));

        float prevExposure = texelFetch(colortex5, ivec2(skyViewRes.x, 4), 0).x;

        /* if (prevExposure > 1e-8)  */{
            float fadedSpeed = targetExposure > prevExposure ? EXPOSURE_SPEED_DOWN : EXPOSURE_SPEED_UP;
            exposure = mix(targetExposure, prevExposure, fastExp(-fadedSpeed * frameTime));
        // } else {
        //     exposure = targetExposure;
        }
	#else
		exposure = exp2(-MANUAL_EV);
	#endif
}

#else

#define PROGRAM_PREPARE
#define CLOUD_LIGHTING

//======// Output //==============================================================================//

/*
const bool colortex1MipmapEnabled = true;
*/

/* RENDERTARGETS: 5,10 */
layout (location = 0) out vec3 skyViewOut;
layout (location = 1) out vec3 transmittanceOut;

//======// Input //===============================================================================//

noperspective in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in vec3 sunIlluminance;
flat in vec3 moonIlluminance;

flat in float exposure;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler3D COMBINED_TEXTURE_SAMPLER; // Combined atmospheric LUT

uniform float nightVision;
uniform float wetness;
uniform float eyeAltitude;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 worldSunVector;
uniform vec3 worldLightVector;
uniform vec3 cameraPosition;
uniform vec3 lightningShading;

//======// Function //============================================================================//

#include "/lib/universal/Noise.glsl"

#include "/lib/atmospherics/Global.glsl"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

#include "/lib/atmospherics/Clouds.glsl"

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	if (screenTexel.x == skyViewRes.x) {
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

            default:
                skyViewOut = vec3(0.0);
		}
	} else if (screenTexel.y > skyViewRes.y) {
		// Sky map with clouds

		vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector, transmittanceOut) * 12.0;

		#ifdef CLOUDS_ENABLED
            vec4 cloudData = RenderClouds(worldDir/* , skyViewOut */, 0.5);
            skyViewOut = skyViewOut * cloudData.a + cloudData.rgb;
        #endif
	} else {
		// Raw sky map

		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector, transmittanceOut) * 12.0;
	}
}

#endif