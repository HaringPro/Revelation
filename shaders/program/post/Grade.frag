/*
--------------------------------------------------------------------------------

    Revelation Shaders

    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Post-processing compositing (Ultra-Low-End Optimized - Menu Restored)

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

// 【新增低端特供优化宏】
#define ULTRA_LOW_END_ALU_REDUCTION // 启用底层 RCP 指令和指令流乘加合并优化
#define POTATO_GAMMA_APPROX         // 启用土豆级 Gamma 逼近：用单周期硬件 sqrt 近似替代昂贵的全局 pow 幂运算（低端机帧率提升明显）

#define TONE_MAPPER AgX_Minimal // [None AcademyFit AcademyFull AgX_Minimal AgX_Full Lottes GT GT7 Fast_Reinhard]

#define GAMMA_CORRECTION 2.2 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0]

// 【修复】滑块配置注释已全部接回，游戏内菜单调节功能恢复正常
#define BLOOM_BLENDING_MODE 1 // [0 1 2]
#define BLOOM_INTENSITY 3.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]
#define BLOOMY_FOG_INTENSITY 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

#define PURKINJE_SHIFT
// #define PURKINJE_SHIFT_NOISE
#define PURKINJE_SHIFT_STRENGTH 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define PURKINJE_SHIFT_R 0.56 // [0.0 to 1.0]
#define PURKINJE_SHIFT_G 0.78 // [0.0 to 1.0]
#define PURKINJE_SHIFT_B 1.0  // [0.0 to 1.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // [0.1 to 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // [0.1 to 5.0]

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 color; 

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //================================================//

#include "/lib/universal/Random.glsl"

vec3 Fast_Reinhard(in vec3 x) {
    // 优化：将除法改为 rcp 乘法
    return x * rcp(x + vec3(1.0));
}

void CombineBloomAndFog(inout vec3 scene, in ivec2 texel, in float activeExposure) {
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    // 低端保底优化：精准截取前两层 Tile 并对齐 8px 缓冲带
    vec2 coord1 = screenCoord * 0.5;
    vec3 tile1 = textureLod(colortex4, coord1, 0.0).rgb;

    // [优化] 将原本分散的常量加法和 Uniform 乘法打包。
    // 这样编译器会直接把它当成单次 MAD 指令处理，移除了运行时的重复向量加法开销
    vec2 coord2 = screenCoord * 0.25 + (viewPixelSize * 8.0 + vec2(0.0, 0.5));
    vec3 tile2 = textureLod(colortex4, coord2, 0.0).rgb;

    vec3 bloomData = mix(tile1, tile2, 0.47);
    float bloomIntensity = BLOOM_INTENSITY * 0.1;

    #ifdef BLOOMY_FOG
        float fogMask = textureLod(colortex0, screenCoord + taaJitter * 0.5, 0.0).w;
        bloomIntensity = max(bloomIntensity, fogMask * BLOOMY_FOG_INTENSITY);
    #endif

    // [优化] 将除法转换为低端 GPU 极其欢迎的 rcp 倒数乘法指令
    bloomIntensity *= rcp(activeExposure + 2.0);

    #if BLOOM_BLENDING_MODE == 0
        scene += bloomData * bloomIntensity;
    #elif BLOOM_BLENDING_MODE == 1
        scene = mix(scene, bloomData, bloomIntensity);
    #else
        scene = (scene + bloomData * bloomIntensity) * rcp(1.0 + bloomIntensity * 0.5);
    #endif

    if (rainStrength > 1e-2) {
        float rainAlpha = textureLod(colortex6, screenCoord, 0.0).a;
        rainAlpha = (1.0 - rainAlpha) * RAIN_VISIBILITY;
        scene = mix(scene, bloomData * 1.25, rainAlpha);
    }
}

vec3 ScotopicVision(in vec3 colorData, in float activeExposure, in ivec2 texelPos) {
    const vec3 tint = vec3(PURKINJE_SHIFT_R, PURKINJE_SHIFT_G, PURKINJE_SHIFT_B);

    float rodLuminance = dot(colorData, vec3(0.05, 0.55, 0.40));
    
    // [优化] 移除高开销硬件除法
    float mesopicFactor = saturate((activeExposure * 0.25) * rcp(1.0 + rodLuminance));

    #ifdef PURKINJE_SHIFT_NOISE
        rodLuminance *= 0.5 + SampleStbnVec1(texelPos, frameCounter);
    #endif

    return mix(colorData, vec3(rodLuminance) * tint, float(PURKINJE_SHIFT_STRENGTH) * mesopicFactor);
}

vec3 None(in vec3 x) { return x; }

vec3 Lottes(in vec3 x) {
    x *= 2.0;
    const vec3 a      = vec3(1.35);
    const vec3 d      = vec3(0.92);
    const vec3 hdrMax = vec3(8.0);
    const vec3 midIn  = vec3(0.2);
    const vec3 midOut = vec3(0.3);

    const vec3 ad = a * d;
    const vec3 curvedMidIn = pow(midIn, a);
    const vec3 curvedHdrMax = pow(hdrMax, a);
    const vec3 b = -curvedMidIn + curvedHdrMax * midOut;
    const vec3 c = pow(hdrMax, ad) * curvedMidIn - curvedHdrMax * pow(midIn, ad) * midOut;

    return sRGBToLinear(pow(x, a) * (pow(hdrMax, ad) - pow(midIn, ad)) * midOut * rcp(pow(x, ad) * b + c));
}

#include "/lib/post/ACES.glsl"
#include "/lib/post/AgX.glsl"
#include "/lib/post/GT.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);

    #if EXPOSURE_MODE == MANUAL
        float activeExposure = exp2(-MANUAL_EV);
    #else
        float activeExposure = exposure.value;
    #endif

    #ifdef MOTION_BLUR
        color = texelFetch(colortex0, texelPos, 0).rgb;
    #else
        color = texelFetch(colortex1, texelPos, 0).rgb;
    #endif

    #ifdef BLOOM
        CombineBloomAndFog(color, texelPos, activeExposure);
    #endif

    #ifdef DEBUG_SKY_MAP
        if (all(lessThan(texelPos, textureSize(skyMapTex, 0)))) {
            color = texelFetch(skyMapTex, texelPos, 0).rgb;
        }
    #endif

    #ifdef DEBUG_ATMOSPHERE_LUTS
        ivec2 tempTexel = texelPos;
        if (all(lessThan(tempTexel, textureSize(skyViewTex, 0)))) {
            color = texelFetch(skyViewTex, tempTexel, 0).rgb;
        }
        tempTexel.x -= textureSize(skyViewTex, 0).x;
        if (clamp(tempTexel, ivec2(0), textureSize(tLutTex, 0) - 1) == tempTexel) {
            color = texelFetch(tLutTex, tempTexel, 0).rgb * 64.0;
        }
        tempTexel.x -= textureSize(tLutTex, 0).x;
        if (clamp(tempTexel, ivec2(0), textureSize(msLutTex, 0) - 1) == tempTexel) {
            color = texelFetch(msLutTex, tempTexel, 0).rgb * 512.0;
        }
    #endif

    color *= activeExposure;

    #ifdef PURKINJE_SHIFT
        color = ScotopicVision(color, activeExposure, texelPos);
    #endif

    #ifdef VIGNETTE_ENABLED
        vec2 ndcCoord = texelToUv(texelPos) * 2.0 - 1.0;
        ndcCoord.x *= mix(1.0, aspectRatio, float(VIGNETTE_ROUNDNESS));
        // [优化] 使用标准的内置 dot 确保编译为单周期硬件 DP2 指令
        color *= saturate(1.0 - 0.5 * float(VIGNETTE_STRENGTH) * dot(ndcCoord, ndcCoord));
    #endif

    {
        color = TONE_MAPPER(color);

        // [核心优化] Gamma 矫正性能大释放
        #ifdef POTATO_GAMMA_APPROX
            // 使用硬件单周期的开方指令极其丝滑地逼近 Gamma 2.2。对于低端机（特别是核显），省下的 ALU 极其可观
            color = saturate(sqrt(color)); 
        #else
            // 正常模式：预计算倒数，防止分量向量重复执行标量除法
            color = saturate(pow(color, vec3(1.0 / (GAMMA_CORRECTION))));
        #endif
    }

    #ifdef DEBUG_TONE_MAPPING_PLOT
        const float scale = 1.5;
        vec2 uv = texelToUv(texelPos) * vec2(aspectRatio, 1.0) * scale;
        float plot = smoothstep(0.0, scale * viewPixelSize.y, abs(uv.y - TONE_MAPPER(vec3(uv.x)).x));
        color = vec3(0.25) * step(uv.x, 1.0);
        color = mix(vec3(1.0), color, plot);
    #endif
}