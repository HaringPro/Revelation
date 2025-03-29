/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Compute exposure

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out float exposure;

//======// Attribute //===========================================================================//

in vec3 vaPosition;

//======// Uniform //=============================================================================//

uniform sampler2D colortex0; // Scene data
uniform sampler2D colortex1; // Previous exposure

uniform float frameTime;

uniform vec2 viewSize;

//======// Function //============================================================================//

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

    #if EXPOSURE_MODE == AUTO_HISTOGRAM
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
            float luminance = luminance(textureLod(colortex0, uv, AUTO_EXPOSURE_LOD).rgb);

            float weight = exp2(-0.5 * sdot(uv - 0.5));

            #if EXPOSURE_MODE == AUTO_HISTOGRAM
                // Build luminance bucket
                float bin = histogramLumToBin(luminance);
                lumBucket[uint(bin * float(HISTOGRAM_BIN_COUNT - 1u))] += weight;
            #else
                sum += clamp(log2(luminance), AUTO_EV_MIN, AUTO_EV_MAX) * weight;
            #endif
            sumWeight += weight;
        }
	}

    #if EXPOSURE_MODE == AUTO_HISTOGRAM
        float norm = 1.0 / sumWeight;

        float prefix = 0.0;
        sum = sumWeight = 0.0;

        uint i = 0u;
        for (; i < HISTOGRAM_BIN_COUNT; ++i) {
            prefix += lumBucket[i] * norm;
            if (prefix > HISTOGRAM_LOWER_BOUND) {
                float weight = prefix - HISTOGRAM_LOWER_BOUND;
                sum = float(i) * weight;
                sumWeight = weight;
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

 	#if EXPOSURE_MODE == MANUAL
		exposure = exp2(-MANUAL_EV);
	#else
		float lumimance = CalculateAutoExposure();

        const float K = 22.5; // Calibration constant
        const float calibration = exp2(AUTO_EV_BIAS) * K / ISO;

        float targetExposure = calibration * rcp(lumimance);
        float prevExposure = loadExposure();

        float exposureRate = targetExposure > prevExposure ? EXPOSURE_SPEED_DOWN : EXPOSURE_SPEED_UP;
        exposure = mix(targetExposure, prevExposure, fastExp(-exposureRate * frameTime));
	#endif
}