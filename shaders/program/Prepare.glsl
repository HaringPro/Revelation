/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass:
    - Vertex Shader:   Compute illuminances and exposure
    - Fragment Shader: Compute Sky-View LUT, Transmittance-View LUT, cloud shadows, store illuminances and exposure

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#if defined VERTEX_SHADER

//======// Output //==============================================================================//

noperspective out vec2 screenCoord;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

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
uniform vec3 lightningShading;

//======// Function //============================================================================//

#ifdef AURORA
	float auroraAmount = smoothstep(0.0, 0.2, -worldSunVector.y) * AURORA_STRENGTH;
	vec3 auroraShading = vec3(0.0, 0.005, 0.0025) * auroraAmount;
#endif

#include "/lib/atmospherics/Global.glsl"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

const float autoEvRange = AUTO_EV_MAX - AUTO_EV_MIN;
const float autoEvRangeInv = 1.0 / autoEvRange;

float histogramLumToBin(in float lum) {
    return saturate(log2(lum) * autoEvRangeInv - (AUTO_EV_MIN * autoEvRangeInv));
}

float histogramBinToLum(in float bin) {
    return exp2(bin * (autoEvRange / HISTOGRAM_BIN_COUNT) + AUTO_EV_MIN);
}

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

            float weight = exp2(-0.25 * dotSelf(uv * 2.0 - 1.0));

            #ifdef HISTOGRAM_AE
                // Build luminance bucket
                float bin = histogramLumToBin(luminance);
                lumBucket[uint(bin * float(HISTOGRAM_BIN_COUNT - 1u))] += weight;
            #else
                sum += clamp(log2(luminance), AUTO_EV_MIN, AUTO_EV_MAX) * weight;
            #endif
            sumWeight += weight;
        }
	}

    #ifdef HISTOGRAM_AE
        float norm = 1.0 / sumWeight;

        float prefix = 0.0;
        sum = sumWeight = 0.0;

        uint i = 0u;
        for (; i < HISTOGRAM_BIN_COUNT; ++i) {
            prefix += lumBucket[i] * norm;
            if (prefix > HISTOGRAM_LOWER_BOUND) {
                float weight = prefix - HISTOGRAM_LOWER_BOUND;
                sum = float(i) * weight;
                sumWeight += weight;
                break;
            }
        }
        for (; i < HISTOGRAM_BIN_COUNT; ++i) {
            prefix += lumBucket[i] * norm;
            if (prefix > HISTOGRAM_UPPER_BOUND) {
                float weight = prefix - HISTOGRAM_UPPER_BOUND;
                sum += float(i) * weight;
                sumWeight += weight;
                break;
            }
        }

        sum = histogramBinToLum(sum / sumWeight);
    #else
        sum = exp2(sum / sumWeight);
    #endif

	return sum;
}

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	vec3 camera = vec3(0.0, viewerHeight, 0.0);
	vec3 sunIrradiance, moonIrradiance;
	skyIlluminance = GetSunAndSkyIrradiance(camera, worldSunVector, sunIrradiance, moonIrradiance);

    // Fix the sunlight misalignment at sunrise and sunset
	sunIrradiance *= 1.0 - curve(saturate(1.0 - worldSunVector.y * 32.0));

    // Irradiance to illuminance
	directIlluminance = sunIntensity * (sunIrradiance + moonIrradiance);

    skyIlluminance += lightningShading * 4e-3;
	#ifdef AURORA
		skyIlluminance += auroraShading;
	#endif

 	#ifdef AUTO_EXPOSURE
		exposure = CalculateAutoExposure();

        const float K = 12.5;
        const float cal = K / ISO;
        const float m = 3.5, r = m - 0.01;
        float targetExposure = exp2(AUTO_EV_BIAS) / (m - r * fastExp(-exposure * rcp(cal * r)));

        float prevExposure = texelFetch(colortex5, ivec2(skyViewRes.x, 4), 0).x;

        /* if (prevExposure > 1e-8)  */{
            float blendRate = targetExposure > prevExposure ? EXPOSURE_SPEED_DOWN : EXPOSURE_SPEED_UP;
            exposure = mix(targetExposure, prevExposure, fastExp(-blendRate * frameTime));
        // } else {
        //     exposure = targetExposure;
        }
	#else
		exposure = exp2(-MANUAL_EV);
	#endif
}

#else

#define PASS_PREPARE

//======// Output //==============================================================================//

/*
const bool colortex1MipmapEnabled = true;
*/

/* RENDERTARGETS: 5,10 */
layout (location = 0) out vec3 skyViewOut;
layout (location = 1) out vec4 transmittanceOut;

//======// Input //===============================================================================//

noperspective in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in float exposure;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler3D COMBINED_TEXTURE_SAMPLER; // Combined atmospheric LUT

uniform float nightVision;
uniform float wetness;
uniform float eyeAltitude;
uniform float far;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 worldSunVector;
uniform vec3 worldLightVector;
uniform vec3 cameraPosition;
uniform vec3 lightningShading;

uniform float worldTimeCounter;

#ifdef CLOUD_SHADOWS
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
#endif

//======// Function //============================================================================//

#include "/lib/universal/Noise.glsl"

#include "/lib/atmospherics/Global.glsl"
#include "/lib/atmospherics/PrecomputedAtmosphericScattering.glsl"

#ifdef AURORA
	#include "/lib/atmospherics/Aurora.glsl"
#endif

#include "/lib/atmospherics/clouds/Render.glsl"

#ifdef CLOUD_SHADOWS
    #include "/lib/atmospherics/clouds/Shadows.glsl"
#endif

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    // Store some data in the rightmost column of the texture
	if (screenTexel.x == skyViewRes.x) {
		switch (screenTexel.y) {
            case 0:
                skyViewOut = directIlluminance;
                break;

            case 1:
                skyViewOut = skyIlluminance;
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
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector, transmittanceOut.rgb) * skyIntensity;

		#ifdef CLOUDS
            vec4 cloudData = RenderClouds(worldDir/* , skyViewOut */, 0.5);
            skyViewOut = skyViewOut * cloudData.a + cloudData.rgb;
            transmittanceOut.rgb *= cloudData.a;
        #endif
	} else {
		// Raw sky map

		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector, transmittanceOut.rgb) * skyIntensity;
	}

    // Render cloud shadow map
    #ifdef CLOUD_SHADOWS
        vec3 rayPos = SetupCloudShadowPos(screenCoord);
        transmittanceOut.a = CalculateCloudShadows(rayPos);
    #endif
}

#endif