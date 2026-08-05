/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: 实体受伤时长累积（击杀特效计时器，挂 composite5）
    colortex10.R = 每个像素处受伤实体的"持续变红时长"（秒），未受伤立即归零
    colortex10.G = 全局击杀脉冲剩余时间（秒），仅 (0,0) 处有效

    触发逻辑：每帧仅由 (0,0) 像素对 colortex10.R 做 16x16 稀疏采样取最大值，
    超过阈值且当前无脉冲播放时触发一次新脉冲（可叠加触发，不打断已有脉冲）。
--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Config //==============================================================================//

#include "/config.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 10 */
layout (location = 0) out vec2 hurtDataOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/post/KillRipple.glsl"

void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);

    #ifdef KILL_RIPPLE
        // ---- 逐像素：受伤时长累计（时间反馈，读到的是上一帧数据） ----
        float prevTimer = clamp(texelFetch(colortex10, texelPos, 0).r, 0.0, KILL_RIPPLE_TIMER_CAP);

        uvec4 matPack = texelFetch(colortex7, texelPos, 0);
        uint matW = matPack.w;
        bool isHurtEntity = ((matW & 1u) != 0u) && ((matW & 2u) != 0u) && matPack.y != 1u;

        float newTimer = isHurtEntity ? min(prevTimer + frameTime, KILL_RIPPLE_TIMER_CAP) : 0.0;

        // ---- 全局脉冲状态：仅 (0,0) 像素计算（每帧一次），其余像素 G 通道写 0 ----
        float newPulse = 0.0;
        if (texelPos == ivec2(0, 0)) {
            float prevPulse = clamp(texelFetch(colortex10, ivec2(0, 0), 0).g, 0.0, KILL_RIPPLE_DURATION);
            newPulse = max(0.0, prevPulse - frameTime);

            // 无脉冲播放时稀疏采样：16x16 网格取最大受伤时长，越界即触发新脉冲
            if (newPulse <= 0.0) {
                float maxTimer = 0.0;
                const int grid = KILL_RIPPLE_GRID;
                for (int gy = 0; gy < grid && maxTimer < KILL_RIPPLE_TRIGGER_TIME; ++gy) {
                    int sy = min(int((gy + 0.5) * viewHeight / float(grid)), int(viewHeight) - 1);
                    for (int gx = 0; gx < grid && maxTimer < KILL_RIPPLE_TRIGGER_TIME; ++gx) {
                        int sx = min(int((gx + 0.5) * viewWidth / float(grid)), int(viewWidth) - 1);
                        maxTimer = max(maxTimer, clamp(texelFetch(colortex10, ivec2(sx, sy), 0).r, 0.0, KILL_RIPPLE_TIMER_CAP));
                    }
                }
                if (maxTimer >= KILL_RIPPLE_TRIGGER_TIME) {
                    newPulse = KILL_RIPPLE_DURATION;
                }
            }
        }

        hurtDataOut = vec2(newTimer, newPulse);
    #else
        hurtDataOut = vec2(0.0);
    #endif
}
