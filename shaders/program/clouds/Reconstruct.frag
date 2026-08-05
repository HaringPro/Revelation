/*
--------------------------------------------------------------------------------

    Revelation Shaders

    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Reference: https://publications.lib.chalmers.se/records/fulltext/241770/241770.pdf
               https://www.advances.realtimerendering.com/s2019/slides_public_release.pptx

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 9,13 */
layout (location = 0) out vec4 cloudOut;
layout (location = 1) out uint frameOut;

//======// Uniform //=============================================================================//

uniform sampler2D cloudOriginTex;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/clouds/Common.glsl"

// ---------------------------------------------------------------------------
// 性能选项：控制历史缓冲的滤波质量
//   0 - 点采样（最快，但可能有锯齿）
//   1 - 双线性（较快，较平滑）
//   2 - 双三次（平衡，原输出路径的质量）
//   3 - Catmull-Rom（最高质量，原历史采样，性能消耗最大）
// ---------------------------------------------------------------------------
#ifndef CLOUD_TAAU_HISTORY_FILTER
    #define CLOUD_TAAU_HISTORY_FILTER 1
#endif

// 重投影函数（保持原有逻辑）
vec3 ReprojectClouds(in vec2 coord, in float depth) {
    vec3 cloudPos = ScreenToViewDirRaw(coord) * depth;
    cloudPos = transMAD(gbufferModelViewInverse, cloudPos); // To world space

    vec3 motionVector = vec3(0.0);

    // Apply wind
    float radius = depth + atmosphereViewHeight;
    if (radius < cloudMidRadius) {
        // Low clouds
        const float windAngle = radians(CLOUD_LOW_WIND_ANGLE);
        const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
        const vec3 windVelocity = windDir * CLOUD_LOW_WIND_SPEED;
        motionVector -= windVelocity;
    } else if (radius < cloudHighRadius) {
        // Mid clouds
        const float windAngle = radians(CLOUD_MID_WIND_ANGLE);
        const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_MID_WIND_SPEED;
        motionVector.xz -= windVelocity;
    } else {
        // High clouds
        const float windAngle = radians(CLOUD_HIGH_WIND_ANGLE);
        const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_HIGH_WIND_SPEED;
        motionVector.xz -= windVelocity;
    }
    motionVector *= (worldTime - global.prevWorldTime) * 0.05;
    motionVector += cameraMovement;

    cloudPos += motionVector; // To previous frame's world space
    cloudPos = transMAD(gbufferPreviousModelView, cloudPos); // To previous frame's view space
    cloudPos = projMAD(gbufferPreviousProjection, cloudPos) * rcp(-cloudPos.z); // To previous frame's NDC space

    return cloudPos * 0.5 + 0.5;
}

//======// Main //================================================================================//
void main() {
    // x: sunlight, y: skylight, z: depth, w: transmittance
    cloudOut = vec4(0.0, 0.0, 1e6, 1.0);
    frameOut = 0u;

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
    vec2 currCoord = screenCoord - taaJitter * (0.5 * float(CLOUD_TAAU_SCALE));

    // Fetch closest cloud depth (component 2 = depth)
    float cloudDepth = minOf(textureGather(cloudOriginTex, currCoord, 2));

    // Skip ground
    if (cloudDepth < EPS) return;

    frameOut = 1u;

    vec2 prevCoord = ReprojectClouds(screenCoord, cloudDepth).xy;
    uint frameIndex = texture(colortex13, prevCoord).x;

    bool disocclusion = worldTimeChanged;
    // Offscreen invalidation
    disocclusion = disocclusion || saturate(prevCoord) != prevCoord;
    // Previous ground invalidation
    disocclusion = disocclusion || frameIndex < 1u;

    if (disocclusion) {
        // 重置时根据性能选项输出当前帧（此处保持双三次以获得较好起点）
        #if CLOUD_TAAU_HISTORY_FILTER <= 1
            cloudOut = textureLod(cloudOriginTex, currCoord, 0.0);
        #else
            cloudOut = textureBicubic(cloudOriginTex, currCoord);
        #endif
    } else {
        ivec2 currTexel = uvToTexel(currCoord) / CLOUD_TAAU_SCALE;
        vec4 currData = texelFetch(cloudOriginTex, currTexel, 0);

        // 根据选项采样历史缓冲
        vec4 prevData;
        #if CLOUD_TAAU_HISTORY_FILTER == 0
            prevData = texelFetch(cloudReconstructTex, ivec2(prevCoord * textureSize(cloudReconstructTex, 0)), 0);
        #elif CLOUD_TAAU_HISTORY_FILTER == 1
            prevData = textureLod(cloudReconstructTex, prevCoord, 0.0);
        #elif CLOUD_TAAU_HISTORY_FILTER == 2
            prevData = textureBicubic(cloudReconstructTex, prevCoord);
        #else // 3: Catmull-Rom (original)
            prevData = max0(textureCatmullRom(cloudReconstructTex, prevCoord));
        #endif

        #ifdef CLOUD_TAAU_CLIPPING
            vec4 moment1 = currData;
            vec4 moment2 = currData * currData;

            // Fetch 3x3 neighbour pixels
            for (uint i = 0u; i < 8u; ++i) {
                vec4 sampleData = texelFetch(cloudOriginTex, currTexel + offset3x3N[i], 0);
                moment1 += sampleData;
                moment2 += sampleData * sampleData;
            }
            moment1 *= rcp(9.0);
            moment2 *= rcp(9.0);

            // Ellipsoid intersection clipping
            vec4 clipStdDevInv = inversesqrt(abs(moment2 - moment1 * moment1) + EPS);
            prevData -= moment1;
            prevData *= saturate(inversesqrt(sdot(prevData * clipStdDevInv * 0.25)));
            prevData += moment1;
        #endif

        // Fix depth edge artifacts
        currData.z *= 1.0 - currData.w;
        prevData.z *= 1.0 - prevData.w;

        // Accumulate
        frameOut = min(frameIndex + 1u, CLOUD_MAX_ACCUM_FRAMES);
        cloudOut = mix(prevData, currData, rcp(float(frameOut)));

        // Fix depth edge artifacts
        cloudOut.z /= maxEps(1.0 - cloudOut.w);
    }
}