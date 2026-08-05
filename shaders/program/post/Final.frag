/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Contrast adaptive sharpening and final output 
          (Startup Logo + Screen Hurt FX + Entity Area Glitch)
    Uses low 2 bits of materialOut.w for entity/hurt flags.
    Added: GLITCH_TEAR_LAYERS, ALWAYS_GLITCH macro.
--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//
#include "/lib/Utility.glsl"
//======// Config //==============================================================================//
#include "/config.glsl"
//======// Output //==============================================================================//
out vec3 finalOut;
//======// Uniform //=============================================================================//
#include "/lib/universal/Uniform.glsl"
//======// SSBO //================================================================================//
#define SSBO_DECLARED_TPYE restrict
#include "/lib/universal/SSBO.glsl"
//======// Function //============================================================================//
#include "/lib/universal/Random.glsl"

#include "/lib/post/KillRipple.glsl"

#define STARTUP_LOGO
#define LOGO_SCALE 5.0
#ifdef STARTUP_LOGO
uniform sampler2D startupTex;
#endif

// ---------- 调试：始终显示全屏故障（取消注释即生效） ----------
//#define ALWAYS_GLITCH

// ---------- 全屏受伤故障 ----------
#define GLITCH_VISUAL
#define HURT_GLITCH_INTENSITY 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// ---------- 实体区域故障 ----------
#define ENTITY_AREA_GLITCH
#define ENTITY_AREA_GLITCH_INTENSITY 0.6 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// ---------- 撕裂层数（推荐 2~6） ----------
#define GLITCH_TEAR_LAYERS 6 // [2 3 4 5 6 7 8 9 10 11 12 13 14 15 16]

// ---------- 实体撕裂模式 ----------
#define ENTITY_GLITCH_OUTLINE_TEAR // [注释以关闭] 开启：实体轮廓随条带一起撕裂（缺口用邻近背景近似填充）；关闭：旧版仅内部颜色错位

uniform bool is_hurt;

vec3 FFXCasFilter(in ivec2 texel, in float sharpness) {
    #define CasLoad(offset) texelFetchOffset(colortex0, texel, 0, offset).rgb
    #ifndef CAS_ENABLED
        return CasLoad(ivec2(0, 0));
    #endif
    vec3 e = CasLoad(ivec2( 0,  0));
    vec3 b = CasLoad(ivec2( 0, -1));
    vec3 d = CasLoad(ivec2(-1,  0));
    vec3 f = CasLoad(ivec2( 1,  0));
    vec3 h = CasLoad(ivec2( 0,  1));
    vec3 minCol = min(min(min(d, e), min(f, b)), h);
    vec3 maxCol = max(max(max(d, e), max(f, b)), h);
    vec3 a = CasLoad(ivec2(-1, -1));
    vec3 c = CasLoad(ivec2( 1, -1));
    vec3 g = CasLoad(ivec2(-1,  1));
    vec3 i = CasLoad(ivec2( 1,  1));
    minCol += min(min(min(a, c), min(g, i)), minCol);
    maxCol += max(max(max(a, c), max(g, i)), maxCol);
    vec3 amp = sqrt(saturate(min(minCol, 2.0 - maxCol) / maxCol));
    vec3 w = amp * -(1.0 / mix(8.0, 5.0, sharpness));
    return saturate(((b + d + f + h) * w + e) / (1.0 + 4.0 * w));
}

#include "/lib/universal/TextRenderer.glsl"
void HistogramDisplay(inout vec3 color, in ivec2 texel) {
    const int binWidth = 2;
    if (all(lessThan(texel, ivec2(HISTOGRAM_BIN_COUNT * binWidth, 256)))) {
        int binIndex = texel.x / binWidth;
        uint binValue = exposure.histogram[binIndex];
        color = vec3(step(texel.y + 1, binValue));
    }
}

float loop(float x) {
    x = mix(x, x - 1.0, float(x > 1.0));
    x = mix(x, x + 1.0, float(x < 0.0));
    return x;
}

void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);
    if (texelPos == ivec2(0)) { global.prevWorldTime = worldTime; }

    #ifdef DEBUG_BLOOM_TILES
        finalOut = texelFetch(colortex4, texelPos, 0).rgb;
    #else
        finalOut = FFXCasFilter(texelPos, CAS_STRENGTH);
    #endif

    // 启动图片淡出
    #ifdef STARTUP_LOGO
        const int logoDuration = 180, fadeStart = 60;
        if (frameCounter < logoDuration) {
            float fade = 1.0 - smoothstep(float(fadeStart), float(logoDuration), float(frameCounter));
            ivec2 texSize = textureSize(startupTex, 0);
            ivec2 logoSize = ivec2(vec2(texSize) * LOGO_SCALE);
            ivec2 startPos = ivec2(viewSize) / 2 - logoSize / 2;
            ivec2 logoCoord = texelPos - startPos;
            if (all(greaterThanEqual(logoCoord, ivec2(0))) && all(lessThan(logoCoord, logoSize))) {
                ivec2 srcCoord = ivec2(logoCoord / LOGO_SCALE);
                srcCoord.y = texSize.y - 1 - srcCoord.y;
                vec4 logoColor = texelFetch(startupTex, srcCoord, 0);
                finalOut = mix(finalOut, logoColor.rgb, logoColor.a * fade);
            }
        }
    #endif

    // ========== 实体区域故障 ==========
    #ifdef ENTITY_AREA_GLITCH
        uvec4 matPack = texelFetch(colortex7, texelPos, 0);
        uint matW = matPack.w;
        bool isEntity = ((matW & 1u) != 0u);          // bit0
        bool isHurt   = ((matW & 2u) != 0u);          // bit1

        float intensity = ENTITY_AREA_GLITCH_INTENSITY;
        vec2 uv = (vec2(texelPos) + 0.5) / vec2(viewWidth, viewHeight);
        float seed = floor(frameTimeCounter * 16.0);
        float r1 = fract(sin(seed * 0.012989) * 43758.5453123);
        float r2 = fract(sin(r1 * 2.0 * 0.012989) * 43758.5453123);
        float r3 = fract(sin(r2 * 3.0 * 0.012989) * 43758.5453123);
        float r4 = fract(sin(r3 * 4.0 * 0.012989) * 43758.5453123);
        float r5 = fract(sin(r4 * 5.0 * 0.012989) * 43758.5453123);
        float r6 = fract(sin(r5 * 6.0 * 0.012989) * 43758.5453123);
        float r7 = fract(sin(r6 * 7.0 * 0.012989) * 43758.5453123);

        // 多层撕裂
        const int layers = GLITCH_TEAR_LAYERS;
        float offsetAccum = 0.0;
        for (int i = 0; i < layers; i++) {
            float fi = float(i);
            float threshold = fract(sin(r1 * (12.9898 + fi) + r2 * (78.233 - fi)) * 43758.5453);
            threshold = threshold * 0.6 + 0.2;
            float seg = mix(r3, mix(r4, r5, step(threshold, uv.y)), step(1.0 - threshold, uv.y));
            offsetAccum += seg;
        }
        offsetAccum /= float(layers);
        offsetAccum = (offsetAccum * 2.0 - 1.0) * 0.15;

        #ifdef ENTITY_GLITCH_OUTLINE_TEAR
            // ===== 新撕裂：实体轮廓随条带一起水平位移，缺口用邻近背景近似填充 =====
            // 内容来源像素 = 当前像素 - 条带位移（像素）。来源处是受伤实体则被拖拽到当前位置；
            // 当前是实体但来源不是（条带移走后的缺口），则用来源处的背景像素近似填充
            ivec2 srcTexel = texelPos;
            srcTexel.x -= int(round(offsetAccum * intensity * float(viewWidth)));
            srcTexel.x = clamp(srcTexel.x, 0, int(viewWidth) - 1);
            uvec4 srcPack = texelFetch(colortex7, srcTexel, 0);
            uint srcW = srcPack.w;
            bool srcIsEntity = ((srcW & 1u) != 0u) && ((srcW & 2u) != 0u) && srcPack.y != 1u;
            if (srcIsEntity || (isEntity && isHurt && matPack.y != 1u)) {
                float shiftUv = offsetAccum * intensity;
                float uvR = loop(uv.x - (shiftUv + r6 * 0.1));
                float uvG = loop(uv.x - shiftUv);
                float uvB = loop(uv.x - (shiftUv - r7 * 0.1));

                vec3 glitchColor;
                glitchColor.r = texture(colortex0, vec2(uvR, uv.y)).r;
                glitchColor.g = texture(colortex0, vec2(uvG, uv.y)).g;
                glitchColor.b = texture(colortex0, vec2(uvB, uv.y)).b;

                finalOut = glitchColor;
            }
        #else
            // ===== 旧撕裂：仅实体内部颜色错位，轮廓保持不动 =====
            if (isEntity && isHurt && matPack.y != 1u) {
                float uvR = loop(uv.x + (offsetAccum - r6 * 0.1) * intensity);
                float uvG = loop(uv.x + offsetAccum * intensity);
                float uvB = loop(uv.x + (offsetAccum + r7 * 0.1) * intensity);

                vec3 glitchColor;
                glitchColor.r = texture(colortex0, vec2(uvR, uv.y)).r;
                glitchColor.g = texture(colortex0, vec2(uvG, uv.y)).g;
                glitchColor.b = texture(colortex0, vec2(uvB, uv.y)).b;

                finalOut = mix(finalOut, glitchColor, intensity);
            }
        #endif
    #endif

    // ========== 全屏受伤故障（支持始终显示） ==========
    #ifdef GLITCH_VISUAL
        // ALWAYS_GLITCH 开启时无视 is_hurt，强制显示故障
        #ifdef ALWAYS_GLITCH
            const float intensity = HURT_GLITCH_INTENSITY;
            vec2 uv = (vec2(texelPos) + 0.5) / vec2(viewWidth, viewHeight);
            float seed = floor(frameTimeCounter * 16.0);
            float r1 = fract(sin(seed * 0.012989) * 43758.5453123);
            float r2 = fract(sin(r1 * 2.0 * 0.012989) * 43758.5453123);
            float r3 = fract(sin(r2 * 3.0 * 0.012989) * 43758.5453123);
            float r4 = fract(sin(r3 * 4.0 * 0.012989) * 43758.5453123);
            float r5 = fract(sin(r4 * 5.0 * 0.012989) * 43758.5453123);
            float r6 = fract(sin(r5 * 6.0 * 0.012989) * 43758.5453123);
            float r7 = fract(sin(r6 * 7.0 * 0.012989) * 43758.5453123);

            // 多层撕裂
            const int layers = GLITCH_TEAR_LAYERS;
            float offsetAccum = 0.0;
            for (int i = 0; i < layers; i++) {
                float fi = float(i);
                float threshold = fract(sin(r1 * (12.9898 + fi) + r2 * (78.233 - fi)) * 43758.5453);
                threshold = threshold * 0.6 + 0.2;
                float seg = mix(r3, mix(r4, r5, step(threshold, uv.y)), step(1.0 - threshold, uv.y));
                offsetAccum += seg;
            }
            offsetAccum /= float(layers);
            offsetAccum = (offsetAccum * 2.0 - 1.0) * 0.15;

            float uvR = loop(uv.x + (offsetAccum - r6 * 0.1) * intensity);
            float uvG = loop(uv.x + offsetAccum * intensity);
            float uvB = loop(uv.x + (offsetAccum + r7 * 0.1) * intensity);

            vec3 glitchColor;
            glitchColor.r = texture(colortex0, vec2(uvR, uv.y)).r;
            glitchColor.g = texture(colortex0, vec2(uvG, uv.y)).g;
            glitchColor.b = texture(colortex0, vec2(uvB, uv.y)).b;

            finalOut = mix(finalOut, glitchColor, intensity);
        #else
            if (is_hurt) {
                const float intensity = HURT_GLITCH_INTENSITY;
                vec2 uv = (vec2(texelPos) + 0.5) / vec2(viewWidth, viewHeight);
                float seed = floor(frameTimeCounter * 16.0);
                float r1 = fract(sin(seed * 0.012989) * 43758.5453123);
                float r2 = fract(sin(r1 * 2.0 * 0.012989) * 43758.5453123);
                float r3 = fract(sin(r2 * 3.0 * 0.012989) * 43758.5453123);
                float r4 = fract(sin(r3 * 4.0 * 0.012989) * 43758.5453123);
                float r5 = fract(sin(r4 * 5.0 * 0.012989) * 43758.5453123);
                float r6 = fract(sin(r5 * 6.0 * 0.012989) * 43758.5453123);
                float r7 = fract(sin(r6 * 7.0 * 0.012989) * 43758.5453123);

                // 多层撕裂
                const int layers = GLITCH_TEAR_LAYERS;
                float offsetAccum = 0.0;
                for (int i = 0; i < layers; i++) {
                    float fi = float(i);
                    float threshold = fract(sin(r1 * (12.9898 + fi) + r2 * (78.233 - fi)) * 43758.5453);
                    threshold = threshold * 0.6 + 0.2;
                    float seg = mix(r3, mix(r4, r5, step(threshold, uv.y)), step(1.0 - threshold, uv.y));
                    offsetAccum += seg;
                }
                offsetAccum /= float(layers);
                offsetAccum = (offsetAccum * 2.0 - 1.0) * 0.15;

                float uvR = loop(uv.x + (offsetAccum - r6 * 0.1) * intensity);
                float uvG = loop(uv.x + offsetAccum * intensity);
                float uvB = loop(uv.x + (offsetAccum + r7 * 0.1) * intensity);

                vec3 glitchColor;
                glitchColor.r = texture(colortex0, vec2(uvR, uv.y)).r;
                glitchColor.g = texture(colortex0, vec2(uvG, uv.y)).g;
                glitchColor.b = texture(colortex0, vec2(uvB, uv.y)).b;

                finalOut = mix(finalOut, glitchColor, intensity);
            }
        #endif
    #endif

    // 调试纹理显示
    #ifdef DEBUG_CLOUD_SHADOWS
        if (all(lessThan(texelPos, textureSize(cloudShadowTex, 0)))) {
            finalOut = vec3(texelFetch(cloudShadowTex, texelPos, 0).x);
        }
    #endif
    #ifdef DEBUG_CLOUD_MAP
        ivec2 tempTexel = texelPos;
        if (all(lessThan(tempTexel, textureSize(cloudMapTex, 0)))) {
            finalOut = vec3(texelFetch(cloudMapTex, tempTexel, 0).x);
        }
        tempTexel.x -= textureSize(cloudMapTex, 0).x;
        if (clamp(tempTexel, ivec2(0), textureSize(cloudMapTex, 0) - 1) == tempTexel) {
            finalOut = vec3(texelFetch(cloudMapTex, tempTexel, 0).y);
        }
    #endif
    #ifdef DEBUG_CLOUD_NOISE
        if (all(lessThan(texelPos, textureSize(baseNoiseTex, 0).xy))) {
            finalOut = vec3(texelFetch(baseNoiseTex, ivec3(texelPos, 0), 0).x);
        }
    #endif

    // ========== 击杀特效：实体持续变红超时 → 手部物品脉冲 ==========
    #ifdef KILL_RIPPLE
    float killPulse = texelFetch(colortex10, ivec2(0, 0), 0).g;
    if (killPulse > 0.0) {
        // 手部识别：materialID==1u（手）且深度足够近（排除近处雨雪）
        uvec4 handPack = texelFetch(colortex7, texelPos, 0);
        bool isHand = (handPack.y == 1u) && (loadDepth0(texelPos) < KILL_RIPPLE_HAND_DEPTH);

        // 脉冲进度 0→1，fade 用二次曲线让末尾快速消失
        float killProgress = 1.0 - clamp(killPulse / KILL_RIPPLE_DURATION, 0.0, 1.0);
        float killFade = (1.0 - killProgress) * (1.0 - killProgress);

        // 1) 手部物品整体泛白提亮
        if (isHand) {
            finalOut = mix(finalOut, vec3(1.0), KILL_RIPPLE_HIGHLIGHT * killFade);
        }

        // 2) 扩散涟漪：以当前半径为距离向 8 个方向采样手部 mask，命中即为环上的点
        int ringR = int(round(killProgress * KILL_RIPPLE_RANGE));
        if (ringR > 0) {
            const ivec2 ringDir[8] = ivec2[8](
                ivec2( 1,  0), ivec2(-1,  0), ivec2( 0,  1), ivec2( 0, -1),
                ivec2( 1,  1), ivec2( 1, -1), ivec2(-1,  1), ivec2(-1, -1)
            );
            for (int i = 0; i < 8; ++i) {
                ivec2 ringTexel = texelPos + ringDir[i] * ringR;
                if (clamp(ringTexel, ivec2(0), ivec2(int(viewWidth), int(viewHeight)) - 1) == ringTexel) {
                    uvec4 rp = texelFetch(colortex7, ringTexel, 0);
                    if (rp.y == 1u && loadDepth0(ringTexel) < KILL_RIPPLE_HAND_DEPTH) {
                        finalOut = mix(finalOut, vec3(1.0), killFade);
                        break;
                    }
                }
            }
        }
    }
    #endif

    // ========== 调试：显示击杀特效稀疏采样点 ==========
    #ifdef DEBUG_KILL_RIPPLE_GRID
        const int debugGrid = KILL_RIPPLE_GRID;
        int dgx = clamp(int(floor(float(texelPos.x) * float(debugGrid) / viewWidth)), 0, debugGrid - 1);
        int dgy = clamp(int(floor(float(texelPos.y) * float(debugGrid) / viewHeight)), 0, debugGrid - 1);
        int dsx = min(int((dgx + 0.5) * viewWidth / float(debugGrid)), int(viewWidth) - 1);
        int dsy = min(int((dgy + 0.5) * viewHeight / float(debugGrid)), int(viewHeight) - 1);
        if (all(lessThanEqual(abs(texelPos - ivec2(dsx, dsy)), ivec2(1)))) {
            float debugT = clamp(texelFetch(colortex10, texelPos, 0).r / KILL_RIPPLE_TRIGGER_TIME, 0.0, 1.0);
            finalOut = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), smoothstep(0.5, 1.0, debugT));
        }
    #endif

    finalOut += (bayer16(gl_FragCoord.xy) - 0.5) * rcp255;
    
}