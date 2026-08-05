/*
--------------------------------------------------------------------------------
    Revelation Shaders - Hybrid Temporal Reprojection Anti-Aliasing
    Mode 0 (High Quality): Playdead's variance-clipping & perceptual YCoCg TAA
    Mode 1 (High Performance): MakeUp Fast RGB TAA (fixed history weight)
--------------------------------------------------------------------------------
*/

//======// 配置与宏定义 //=======================================================================//

#define TAA_QUALITY_MODE 1 // [0 1] 0: 高画质模式 (原版 Playdead) | 1: 高性能模式 (MakeUp Fast TAA)

#ifdef TAA_SHARPEN
    #undef TAA_SHARPEN
#endif

//======// 基础引用 //===========================================================================//

#include "/lib/Utility.glsl"

/* RENDERTARGETS: 1,4 */
layout(location = 0) out vec4 temporalOut;
layout(location = 1) out vec3 clearOut;

#ifdef MOTION_BLUR
    /* RENDERTARGETS: 1,4,3 */
    layout(location = 2) out vec2 motionVectorOut;
#endif

#include "/lib/universal/Uniform.glsl"
#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"

//======// 共享辅助函数 //========================================================================//

vec3 CrossClosestFragment(in ivec2 texelPos, in float depth) {
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

//======// 方案 0：高画质模式专属函数 (Playdead YCoCg) //==========================================//
#if TAA_QUALITY_MODE == 0

vec3 perceptualWeight(vec3 colorYCoCg) {
    return colorYCoCg * rcp(1.0 + colorYCoCg.x);
}

vec3 perceptualWeightInv(vec3 colorYCoCg) {
    return colorYCoCg * rcp(1.0 - colorYCoCg.x);
}

vec3 historyClipAABB(in vec3 history, in vec3 center, in vec3 extent) {
    vec3 delta = history - center;
    float maxUnit = maxOf(abs(delta / extent));

    if (maxUnit > 1.0) {
        return center + delta / maxUnit;
    }
    return history;
}

#endif

//======// 方案 1：高性能模式专属函数 (MakeUp RGB ConvexHull，优化版) //===================================//
#if TAA_QUALITY_MODE == 1

// 直接返回裁剪后的 RGB，不再需要 a 通道
vec3 convexHull(
    vec3 c, vec3 previous, vec3 up, vec3 down, vec3 left, vec3 right,
    vec3 ul, vec3 ur, vec3 dl, vec3 dr
) {
    vec3 sum = c + up + down + left + right + ul + ur + dl + dr;
    vec3 sum_sq = c * c + up * up + down * down + left * left + right * right + ul * ul + ur * ur + dl * dl + dr * dr;

    vec3 mean = sum * 0.1111111111111111;
    vec3 variance = abs(sum_sq * 0.1111111111111111 - mean * mean);
    vec3 stdDev = sqrt(variance);
    vec3 minValid = mean - stdDev;
    vec3 maxValid = mean + stdDev;

    return clamp(previous, minValid, maxValid);
}

#endif

// ----------------------------------------------------------------------------
// 核心时序重投影函数
// ----------------------------------------------------------------------------
vec4 TemporalReprojection(in vec2 screenCoord, in vec2 motionVector) {
    ivec2 texel = uvToTexel(screenCoord + taaJitter * 0.5);
    vec2 prevCoord = screenCoord - motionVector;

    // --- 模式 1：高性能 MakeUp Fast TAA（固定高历史权重） ---
    #if TAA_QUALITY_MODE == 1
        vec3 currentRGB = YCoCgToRGB(loadSceneMain(texel));

        if (saturate(prevCoord) != prevCoord)
            return vec4(currentRGB, 1.0);

        vec4 temporalData = texture(colortex1, prevCoord);
        vec3 previousRGB = temporalData.rgb;

        #define FETCH_NEIGHBOUR(off) YCoCgToRGB(texelFetch(colortex0, texel + (off), 0).rgb)
        vec3 up    = FETCH_NEIGHBOUR(ivec2( 0,  1));
        vec3 down  = FETCH_NEIGHBOUR(ivec2( 0, -1));
        vec3 left  = FETCH_NEIGHBOUR(ivec2(-1,  0));
        vec3 right = FETCH_NEIGHBOUR(ivec2( 1,  0));
        vec3 ul    = FETCH_NEIGHBOUR(ivec2(-1,  1));
        vec3 ur    = FETCH_NEIGHBOUR(ivec2( 1,  1));
        vec3 dl    = FETCH_NEIGHBOUR(ivec2(-1, -1));
        vec3 dr    = FETCH_NEIGHBOUR(ivec2( 1, -1));
        #undef FETCH_NEIGHBOUR

        vec3 previousClipped = convexHull(currentRGB, previousRGB, up, down, left, right, ul, ur, dl, dr);

        float accumFrames = min(++temporalData.a, TAA_MAX_ACCUM_FRAMES);

        // 固定历史权重 0.9，新帧 0.1，极大减轻噪点
        const float historyWeight = 0.9;
        #ifdef MOTION_BLUR
            float velocity = length(prevCoord - screenCoord) * 10.0;
            float blendFactor = clamp(historyWeight - velocity * 0.02, 0.0, 1.0);
        #else
            float blendFactor = historyWeight;
        #endif

        return vec4(mix(currentRGB, previousClipped, blendFactor), temporalData.a);

    // --- 模式 0：高画质 Playdead YCoCg TAA（裁剪默认关闭） ---
    #else
        vec3 currData = loadSceneMain(texel);

        if (saturate(prevCoord) != prevCoord) 
            return vec4(YCoCgToRGB(currData), 1.0);

        #ifdef TAA_SHARPEN
            vec4 temporalData = textureCatmullRomFastAntiRing(colortex1, prevCoord);
        #else
            vec4 temporalData = texture(colortex1, prevCoord);
        #endif

        vec3 prevData = RGBToYCoCg(temporalData.rgb);

        float currLum = currData.x, prevLum = prevData.x;
        float temporalContrast = saturate(abs(currLum - prevLum) / max(currLum, prevLum));

        // 默认不裁剪（原版行为），拖影问题因此消失
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

            // 椭球交集裁剪
            prevData -= moment1;
            prevData *= saturate(inversesqrt(sdot(prevData / clipStdDev)));
            prevData += moment1;
        #endif

        // 次像素锐化
        prevData = mix(prevData, currData, sdot(fract(prevCoord * viewSize) - 0.5) * 0.5);

        float blendWeight = min(++temporalData.a, TAA_MAX_ACCUM_FRAMES);
        blendWeight *= 1.0 + sqr(temporalContrast) * TAA_ANTIFLICKER;

        currData = mix(perceptualWeight(prevData), perceptualWeight(currData), rcp(blendWeight));
        return vec4(YCoCgToRGB(perceptualWeightInv(currData)), temporalData.a);
    #endif
}

//======// 主函数入口 //==========================================================================//
void main() {
    clearOut = vec3(0.0);

    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
    float depth = loadDepth0(screenTexel);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    #if RENDER_MODE == 1
        vec2 motionVector;
        #if defined LOD_MOD
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
        // 手持物品等特殊渲染模式的快速混合逻辑
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