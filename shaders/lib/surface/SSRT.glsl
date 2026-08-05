// Reference:
// Morgan McGuire, Michael Mara. "Efficient GPU Screen-Space Ray Tracing". JCGT, 2014.
// https://jcgt.org/published/0003/04/04/paper.pdf

#define SSRT_MAX_SAMPLES 6 // [1 2 4 6 8 12 16 18 20 24 28 32 36 40 48 64 128 256 512]
#define SSRT_SKY_TRACING

// #define SSRT_REFINEMENT
#define SSRT_REFINEMENT_STEPS 4 // [0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]

//================================================================================================//

// 快速归一化（替代 fastNormalize）
float rcpLengthFast(vec3 v) {
    return inversesqrt(max(dot(v, v), 1e-8));
}

bool ScreenSpaceRaytrace(in vec3 viewPos, in vec3 viewDir, in float dither, in uint steps, inout vec3 screenPos) {
    vec3 origin = screenPos;

    // ---- 确保 near、viewSize、viewPixelSize 可用 ----
    #ifndef near
        const float near = 0.05;
    #endif
    #ifndef viewSize
        vec2 viewSize = vec2(viewWidth, viewHeight);
    #endif
    #ifndef viewPixelSize
        vec2 viewPixelSize = 1.0 / viewSize;
    #endif

    // ---- 计算最大行进距离（与原逻辑一致） ----
    float fixZ = step(viewDir.z, 0.0) * 1e23 - (viewPos.z + near) / viewDir.z;
    vec3 rayDir = normalize(ViewToScreenPos(viewDir * fixZ + viewPos) - origin);
    rayDir *= minOf((step(0.0, rayDir) - origin) / rayDir);

    // 转换到像素空间，避免宽高比失真
    rayDir.xy *= viewSize;
    origin.xy *= viewSize;

    float rSteps = 1.0 / float(steps);
    float invDirZ = rcp(abs(rayDir.z));
    vec3 rayStep = rayDir * rSteps;

    // ---- 天空深度宏处理 ----
    #if defined LOD_MOD
        float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
    #else
        float screenDepthSky = 1.0;
    #endif

    bool hit = false;

    float t = dither * rSteps;
    for (uint i = 0u; i < steps; ++i) {
        vec3 rayPos = origin + rayDir * t;

        // 超出像素空间边界则失败
        if (clamp(rayPos.xy, vec2(0.0), viewSize - 1.0) != rayPos.xy) break;

        // 命中天空处理
        if (rayPos.z >= screenDepthSky) {
        #ifdef SSRT_SKY_TRACING
            screenPos = rayPos;
            hit = true;
        #endif
            break;
        }

        // 采样深度
        float sampleDepth = loadDepth2(ivec2(rayPos.xy));
        #if defined LOD_MOD
            if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(ivec2(rayPos.xy))));
        #endif

        // ---- 核心：视图空间厚度过滤（防拉丝） ----
        if (rayPos.z > sampleDepth) {
            float sampleViewZ = ScreenToViewDepth(sampleDepth);
            float stepViewZ = ScreenToViewDepth(rayPos.z);

            if (distance(sampleViewZ, stepViewZ) < -0.2 * stepViewZ) {
                screenPos = rayPos;
                hit = true;
                break;
            }
        } else {
            t += clamp((sampleDepth - rayPos.z) * invDirZ, rSteps * 0.01, rSteps * 1.25);
        }
    }

    // ---- 二分细化（必须开启） ----
    #ifdef SSRT_REFINEMENT
    if (hit) {
        for (uint i = 0u; i < SSRT_REFINEMENT_STEPS; ++i) {
            rayStep *= 0.5;
            float sampleDepth = loadDepth2(ivec2(screenPos.xy));
            #if defined LOD_MOD
                if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth1Lod(ivec2(screenPos.xy))));
            #endif
            // 替换 signMul 为条件表达式
            screenPos += (sampleDepth < screenPos.z) ? -rayStep : rayStep;
        }
    }
    #endif

    // 从像素空间转回屏幕空间坐标 [0,1]
    screenPos.xy *= viewPixelSize;

    return hit;
}
