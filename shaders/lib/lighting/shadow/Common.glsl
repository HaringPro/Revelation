// --- 阴影设置 ---
#define SHADOW_DISTORTION          // [OFF ON] 阴影形变开关
#define SHADOW_DISTORTION_STRENGTH 4.0 // [1.0 1.5 2.0 2.25 2.5 2.75 3.0 3.25 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0]

// 计算形变因子的函数
float CalcDistortionFactor(in vec2 shadowClipPos) {
    #ifndef SHADOW_DISTORTION
        return 1.0; // 如果开关关闭，直接返回1.0，不进行任何形变计算
    #else
        // 原始形变算法
        float invClipLength = inversesqrt(sdot(shadowClipPos));
        float distortionCurve = log((exp(SHADOW_DISTORTION_STRENGTH) - 1.0) / invClipLength + 1.0);
        return distortionCurve * invClipLength * rcp(SHADOW_DISTORTION_STRENGTH);
    #endif
}

// 形变应用函数（重载1）
vec3 DistortShadowSpace(in vec3 shadowClipPos, in float distortionFactor) {
    #ifndef SHADOW_DISTORTION
        return shadowClipPos; // 开关关闭时，不乘以系数，保持原始坐标
    #else
        return shadowClipPos * vec3(vec2(distortionFactor), 0.2);
    #endif
}

// 形变应用函数（重载2）
vec3 DistortShadowSpace(in vec3 shadowClipPos) {
    #ifndef SHADOW_DISTORTION
        return shadowClipPos; // 同上
    #else
        float distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
        return shadowClipPos * vec3(vec2(distortionFactor), 0.2);
    #endif
}