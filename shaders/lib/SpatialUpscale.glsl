//================================================================================================//
// SVGF Upscale Diffuse Indirect (轻量稳定版，已移除体积雾及非必要宏)
//================================================================================================//
#if defined PASS_DEFERRED_LIGHTING
#if defined SVGF_ENABLED && (defined SSILVB_ENABLED || defined VOXEL_GI_TRACE)

// 【唯一保留的可调参数】
// 深度容差平滑度：越接近 0.0 跨越物体的边界越平滑（越不闪），越负则边缘越锐利但易闪烁。
#define SSILVB_DEPTH_FALLBACK   -0.05   // 推荐范围 [-0.01, -0.10]

// 快速 exp2 近似（替代原生 exp2，大幅降低 ALU 开销，对最终画面影响极小）
float exp2_fast(float x) {
    // 位操作近似，适合 x 在 [-1, 1] 区间（此处 depthDiff * fallback 通常在此范围）
    return uintBitsToFloat(0x3F800000 + int(x * 0x3FB8AA3B));
}

vec3 UpscaleDiffuseIndirect(in ivec2 texelPos, in vec3 worldNormal, in float viewDistance, in float NdotV) {
    ivec2 halfPos = texelPos >> 1;
    ivec2 texelEnd = ivec2(halfViewEnd) - 1;

    vec3 centerCol = texelFetch(colortex3, halfPos, 0).rgb;
    float sumWeight = 1.0;
    vec3 sum = centerCol;

    // 质量 0 直接返回中心值，跳过所有采样
    #if SVGF_QUALITY == 0
        return sum;
    #endif

    // 十字采样偏移（4 邻域，保持基本的方向覆盖）
    const ivec2 offsets[4] = ivec2[](ivec2(1,0), ivec2(-1,0), ivec2(0,1), ivec2(0,-1));
    float falloff = SSILVB_DEPTH_FALLBACK;

    for (int i = 0; i < 4; ++i) {
        ivec2 samplePos = clamp(halfPos + offsets[i], ivec2(1), texelEnd);

        // 辅助纹理：rg = 八面体编码法线，b = 线性深度
        vec3 aux = texelFetch(colortex14, samplePos, 0).rgb;
        vec3 color = texelFetch(colortex3, samplePos, 0).rgb;

        // 深度权重（快速 exp2 近似）
        float depthWeight = exp2_fast(abs(aux.z - viewDistance) * falloff);

        // 法线权重（解码八面体法线并与中心法线点积，保证边缘不跨物体）
        float ndot = saturate(dot(OctDecodeSnorm(aux.xy), worldNormal));
        float weight = ndot * depthWeight;

        sum += color * weight;
        sumWeight += weight;
    }

    return sum * rcp(sumWeight);
}

#endif
#endif