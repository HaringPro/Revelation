/*
--------------------------------------------------------------------------------
    Revelation Shaders - FXAA (Fast Approximate Anti-Aliasing) 3.11 简化版
    用于 Final 阶段，在 RGB 空间直接执行空间抗锯齿
    控制宏: #define FXAA_ENABLED  （在 final.fsh 或 config.glsl 中定义）
--------------------------------------------------------------------------------
*/

#ifndef FXAA_GLSL_INCLUDED
#define FXAA_GLSL_INCLUDED

const float FXAA_REDUCE_MIN = 1.0 / 128.0;
const float FXAA_REDUCE_MUL = 1.0 / 8.0;
const float FXAA_SPAN_MAX   = 8.0;

vec3 applyFXAA(in vec2 screenCoord, in sampler2D sceneTex) {
    vec2 pixelSize = vec2(1.0) / vec2(viewWidth, viewHeight);

    // 中心像素（已经是 RGB 颜色）
    vec3 rgbCenter = texture(sceneTex, screenCoord).rgb;
    float lumaCenter = luminance(rgbCenter);

    // 采样十字邻居
    vec3 rgbN = texture(sceneTex, screenCoord + vec2( 0.0,  pixelSize.y)).rgb;
    vec3 rgbS = texture(sceneTex, screenCoord + vec2( 0.0, -pixelSize.y)).rgb;
    vec3 rgbW = texture(sceneTex, screenCoord + vec2(-pixelSize.x,  0.0)).rgb;
    vec3 rgbE = texture(sceneTex, screenCoord + vec2( pixelSize.x,  0.0)).rgb;

    float lumaN = luminance(rgbN);
    float lumaS = luminance(rgbS);
    float lumaW = luminance(rgbW);
    float lumaE = luminance(rgbE);

    // 边缘判定
    float lumaMin = min(lumaCenter, min(min(lumaN, lumaS), min(lumaW, lumaE)));
    float lumaMax = max(lumaCenter, max(max(lumaN, lumaS), max(lumaW, lumaE)));
    float lumaRange = lumaMax - lumaMin;
    if (lumaRange < max(FXAA_REDUCE_MIN, lumaMax * FXAA_REDUCE_MUL)) {
        return rgbCenter;
    }

    // 对角线采样
    vec3 rgbNW = texture(sceneTex, screenCoord + vec2(-pixelSize.x,  pixelSize.y)).rgb;
    vec3 rgbNE = texture(sceneTex, screenCoord + vec2( pixelSize.x,  pixelSize.y)).rgb;
    vec3 rgbSW = texture(sceneTex, screenCoord + vec2(-pixelSize.x, -pixelSize.y)).rgb;
    vec3 rgbSE = texture(sceneTex, screenCoord + vec2( pixelSize.x, -pixelSize.y)).rgb;

    float lumaNW = luminance(rgbNW);
    float lumaNE = luminance(rgbNE);
    float lumaSW = luminance(rgbSW);
    float lumaSE = luminance(rgbSE);

    // 方向对比度
    float hContrast = abs(lumaN + lumaS - 2.0 * lumaCenter) * 0.5 +
                      abs(lumaNW + lumaNE - 2.0 * lumaCenter) * 0.5 +
                      abs(lumaSW + lumaSE - 2.0 * lumaCenter) * 0.5;
    float vContrast = abs(lumaW + lumaE - 2.0 * lumaCenter) * 0.5 +
                      abs(lumaNW + lumaSW - 2.0 * lumaCenter) * 0.5 +
                      abs(lumaNE + lumaSE - 2.0 * lumaCenter) * 0.5;

    // 选择主要方向
    bool isHorizontal = hContrast >= vContrast;

    float lumaP, lumaOpp;
    vec2 dir;
    if (isHorizontal) {
        // 水平方向混合：取左右邻居，沿 X 轴搜索
        lumaP   = lumaW;
        lumaOpp = lumaE;
        dir     = vec2(1.0, 0.0);
    } else {
        // 垂直方向混合：取上下邻居，沿 Y 轴搜索
        lumaP   = lumaN;
        lumaOpp = lumaS;
        dir     = vec2(0.0, 1.0);
    }

    float gradient = abs(lumaP - lumaCenter) * 0.5 + abs(lumaOpp - lumaCenter) * 0.5;
    if (gradient < 0.01) return rgbCenter;

    // 端点搜索
    float stepLength = isHorizontal ? pixelSize.x : pixelSize.y;
    vec3 rgbP = texture(sceneTex, screenCoord + dir * stepLength).rgb;
    vec3 rgbOpp = texture(sceneTex, screenCoord - dir * stepLength).rgb;
    float lumaP2 = luminance(rgbP);
    float lumaOpp2 = luminance(rgbOpp);

    float delta1 = abs(lumaP2 - lumaCenter);
    float delta2 = abs(lumaOpp2 - lumaCenter);
    float subpixelShift = 0.0;
    if (delta1 + delta2 > 1e-5) {
        subpixelShift = (delta2 - delta1) / (2.0 * (delta1 + delta2));
    }

    vec2 blendUV = screenCoord + dir * subpixelShift * stepLength;
    return texture(sceneTex, blendUV).rgb;
}

#endif // FXAA_GLSL_INCLUDED