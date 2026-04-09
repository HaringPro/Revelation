/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

    Pass: Temporal Reprojection Anti-Aliasing
    Reference: https://github.com/playdeadgames/temporal

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 1,4 */
layout (location = 0) out vec4 temporalOut;
layout (location = 1) out vec3 clearOut;

#ifdef MOTION_BLUR
/* RENDERTARGETS: 1,4,3 */
layout (location = 2) out vec2 motionVectorOut;
#endif

//======// Input //===============================================================================//

// flat in float exposure;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"

vec3 CrossClosestFragment(ivec2 texelPos, float depth) {
    vec3 closest = vec3(vec2(texelPos), depth);

    ivec2 t1 = texelPos + ivec2( 1,  1);
    ivec2 t2 = texelPos + ivec2(-1,  1);
    ivec2 t3 = texelPos + ivec2( 1, -1);
    ivec2 t4 = texelPos + ivec2(-1, -1);

    float d1 = loadDepth0(t1);
    float d2 = loadDepth0(t2);
    float d3 = loadDepth0(t3);
    float d4 = loadDepth0(t4);

    closest = closest.z > d1 ? vec3(vec2(t1), d1) : closest;
    closest = closest.z > d2 ? vec3(vec2(t2), d2) : closest;
    closest = closest.z > d3 ? vec3(vec2(t3), d3) : closest;
    closest = closest.z > d4 ? vec3(vec2(t4), d4) : closest;

    closest.xy *= viewPixelSize;
    return closest;
}

// Lumiance aware perceptual weight
vec3 perceptualWeight(vec3 colorYCoCg) {
    return colorYCoCg * rcp(1.0 + colorYCoCg.x);
}

vec3 perceptualWeightInv(vec3 colorYCoCg) {
    return colorYCoCg * rcp(1.0 - colorYCoCg.x);
}

vec3 historyClipAABB(vec3 history, vec3 center, vec3 extent) {
    vec3 delta = history - center;
    float maxUnit = maxOf(abs(delta / extent));

    if (maxUnit > 1.0) {
        return center + delta / maxUnit;
    }

    return history;
}

vec4 TemporalReprojection(vec2 screenCoord, vec2 motionVector) {
    ivec2 texel = uvToTexel(screenCoord + taaJitter * 0.5);

    vec3 currData = loadSceneMain(texel);
    vec2 prevCoord = screenCoord - motionVector;

    if (saturate(prevCoord) != prevCoord) return vec4(YCoCgToRGB(currData), 1.0);

    #ifdef TAA_SHARPEN
        vec4 temporalData = textureCatmullRomFastAntiRing(colortex1, prevCoord);
    #else
        vec4 temporalData = texture(colortex1, prevCoord);
    #endif

    vec3 prevData = RGBToYCoCg(temporalData.rgb);

    float currLum = currData.x, prevLum = prevData.x;
    float temporalContrast = saturate(abs(currLum - prevLum) / max(currLum, prevLum));

    #ifdef TAA_CLIPPING
        vec3 moment1 = currData;
        vec3 moment2 = currData * currData;

	    for (uint i = 0u; i < 8u; ++i) {
            vec3 sampleData = texelFetch(colortex0, texel + offset3x3N[i], 0).rgb;

            moment1 += sampleData;
            moment2 += sampleData * sampleData;
        }
        moment1 *= rcp(9.0);
        moment2 *= rcp(9.0);

        vec3 clipStdDev = sqrt(abs(moment2 - moment1 * moment1)) * TAA_AGGRESSION;

        #if 1
            // Ellipsoid intersection clipping
            prevData -= moment1;
            prevData *= saturate(inversesqrt(sdot(prevData / clipStdDev)));
            prevData += moment1;
        #else
            // AABB clipping
            prevData = historyClipAABB(prevData, moment1, clipStdDev);
        #endif
    #endif

    // Subpixel sharpening
	prevData = mix(prevData, currData, sdot(fract(prevCoord * viewSize) - 0.5) * 0.5);

    float blendWeight = min(++temporalData.a, TAA_MAX_ACCUM_FRAMES);
    blendWeight *= 1.0 + sqr(temporalContrast) * TAA_ANTIFLICKER;

    currData = mix(perceptualWeight(prevData), perceptualWeight(currData), rcp(blendWeight));
    return vec4(YCoCgToRGB(perceptualWeightInv(currData)), temporalData.a);
}

//======// Main //================================================================================//
void main() {
    clearOut = vec3(0.0); // Clear the output buffer for bloom tiles

	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    float depth = loadDepth0(screenTexel);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    #if RENDER_MODE == 1
        vec2 motionVector;
        #if defined LOD_MOD
            // Voxy LoD often does not write vanilla depth (depth ~= 1.0 but non-sky material).
            // Detect it and use DH/VOXY reprojection path instead of fully disabling temporal effects.
            uint materialID = loadMaterialPack(screenTexel).y;
            if (depth > 1.0 - EPS && materialID != 0u) {
                float lodDepth = loadDepth0Lod(screenTexel);
                motionVector = screenCoord - ReprojectScreenPosLod(vec3(screenCoord, lodDepth)).xy;
            } else
        #endif
        {
        #ifdef TAA_CLOSEST_FRAGMENT
            vec3 closestFragment = CrossClosestFragment(screenTexel, depth);
            motionVector = closestFragment.xy - ReprojectScreenPos(closestFragment).xy;
        #else
            motionVector = screenCoord - ReprojectScreenPos(vec3(screenCoord, depth)).xy;
        #endif
        }

        #ifdef MOTION_BLUR
            motionVectorOut = depth < 0.56 ? motionVector * 0.25 : motionVector;
        #endif

        #ifdef TAA_ENABLED
            temporalOut = TemporalReprojection(screenCoord, motionVector);
        #else
            temporalOut = vec4(loadSceneMain(screenTexel), 1.0);
        #endif
    #else
        ivec2 srcTexel = uvToTexel(screenCoord + taaJitter * 0.5);
        temporalOut = vec4(loadSceneMain(srcTexel), 1.0);

        vec2 prevCoord = ReprojectScreenPos(vec3(screenCoord, depth)).xy;
        if (distance(prevCoord, screenCoord) < EPS) {
            vec4 prevData = texture(colortex1, prevCoord);

            temporalOut.rgb = mix(prevData.rgb, temporalOut.rgb, rcp(++prevData.a));
            temporalOut.a = prevData.a;
        }
    #endif
}
