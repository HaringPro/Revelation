#if !defined INCLUDE_WATER_WATERWAVE
#define INCLUDE_WATER_WATERWAVE

const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

// ---------------------------------------------------------------------------
// 噪声采样函数（统一使用硬件双线性过滤，代替昂贵的双三次采样）
// ---------------------------------------------------------------------------
float FetchNoise(in vec2 coord, in float t) {
    coord.y = coord.y * 2.0 + t;
    return sqr(1.0 - texture(noisetex, coord).z);
}

float FetchNoiseFast(in vec2 coord, in float t) {
    coord.y = coord.y * 2.0 + t;
    return sqr(1.0 - texture(noisetex, coord).z);
}

// ---------------------------------------------------------------------------
// 轻量级高度计算（用于阴影等对细节要求不高的 Pass）
// 从 5 层降为 3 层，关闭低频调制时仅需 3 次采样
// ---------------------------------------------------------------------------
float CalculateWaterHeight(in vec2 position) {
    #if RENDER_MODE == 1
        float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
    #else
        float waveTime = 0.0;
    #endif
    vec2 pos = 0.0075 * position;

    float waveHeight = WATER_WAVE_HEIGHT * 0.4;
    #if !defined PASS_SHADOW
        float lfNoise = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
        waveHeight *= saturate(lfNoise * 2.0 - 0.75) + 0.25;
        pos += lfNoise * 0.05;
    #endif

    // 3 层叠加，平衡质量与性能
    float waves = FetchNoise(pos, waveTime);

    pos = goldenRotate * (1.75 * pos) + waves * 0.03;
    waveTime *= 1.25;
    waves += FetchNoise(pos, waveTime) * 0.75;

    pos = goldenRotate * (1.75 * pos) + waves * 0.03;
    waveTime *= 1.25;
    waves += FetchNoise(pos, waveTime) * 0.15;

    // 原先 5 层中最后两层已移除，以提升性能
    return waveHeight * waves;
}

// ---------------------------------------------------------------------------
// 全精度高度计算（用于水表面法线，仍保持 3 层）
// ---------------------------------------------------------------------------
float CalculateWaterHeightFull(in vec2 position) {
    #if RENDER_MODE == 1
        float waveTime = 0.02 * WATER_WAVE_SPEED * frameTimeCounter;
    #else
        float waveTime = 0.0;
    #endif
    vec2 pos = 0.0075 * position;

    float waveHeight = WATER_WAVE_HEIGHT * 0.4;
    #if !defined PASS_SHADOW
        float lfNoise = texture(noisetex, pos * 0.2 + waveTime * 0.1).z;
        waveHeight *= saturate(lfNoise * 2.0 - 0.75) + 0.25;
        pos += lfNoise * 0.05;
    #endif

    float waves = FetchNoiseFast(pos, waveTime);

    pos = goldenRotate * (1.75 * pos) + waves * 0.03;
    waveTime *= 1.25;
    waves += FetchNoiseFast(pos, waveTime) * 0.75;

    pos = goldenRotate * (1.75 * pos) + waves * 0.03;
    waveTime *= 1.25;
    waves += FetchNoiseFast(pos, waveTime) * 0.15;

    // 移除多余细节层，仅保留 3 层
    return waveHeight * waves;
}

// ---------------------------------------------------------------------------
// 水面法线计算（使用全精度高度）
// ---------------------------------------------------------------------------
vec3 CalculateWaterNormal(in vec2 position) {
    const float delta = 0.05;

    float height0 = CalculateWaterHeightFull(position);
    float height1 = CalculateWaterHeightFull(position + vec2(delta, 0.0));
    float height2 = CalculateWaterHeightFull(position + vec2(0.0, delta));

    vec2 waveNormal = vec2(height0 - height1, height0 - height2);
    return normalize(vec3(waveNormal, delta * (1.0 + dot(fwidth(position), vec2(0.2)))));
}

// 重载版本（直接使用平面坐标，忽略光线方向）
vec3 CalculateWaterNormal(in vec3 rayPos, in vec3 rayDir) {
    return CalculateWaterNormal(rayPos.xz);
}

#endif // INCLUDE_WATER_WATERWAVE