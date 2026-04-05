#include "/lib/surface/SSRT.glsl"

// --- 玩家自定义选项 ---
#define FRESNEL_EXPONENT 5.0  // [0.01 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define FRESNEL_STRENGTH 2.0  // [0.01 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]

// --- 核心：反光区间锁定 (防止死白死黑) ---
#define REF_MIN 0.10 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]

#define REF_MAX 0.85 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]


// --- 宏定义 ---
#define REFLECTION_GLOBAL
#define REFLECTION_SCREEN_SPACE
#define REFLECTION_SKY
#define LIGHT_REFLECTION_SAMPLES 10  // [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 24 28 32 36 40 48 64 128 256 512]

vec4 CalculateSpecularReflections(Material material, in vec3 worldNormal, in vec3 screenPos, in vec3 worldDir, in vec3 viewPos, in float skylight, in float dither) {
    
    // 1. 基础视角计算
    vec3 viewDirV = normalize(-viewPos);
    float VdotN = saturate(dot(viewDirV, worldNormal));
    
    // 2. 计算菲涅尔梯度
    float fresnel = pow(1.0 - VdotN, FRESNEL_EXPONENT); 

    // --- [核心逻辑：区间压缩] ---
    // 计算原始亮度输入
    float rawIntensity = (skylight * 0.9 + 0.1) * FRESNEL_STRENGTH;
    
    // 关键点：不再让 center 为 0，不再让 edge 为无穷大
    // 使用 mix 在我们定义的 [MIN, MAX] 区间内插值
    // 这保证了金属表面永远有“灰度差”，也就永远有质感
    float reflectiveLogic = mix(REF_MIN, REF_MAX, fresnel) * rawIntensity;

    // 应用金属度
    vec3 ambientFallback = vec3(reflectiveLogic) * material.metalness;

    // 初始化返回向量
    vec4 reflection = vec4(ambientFallback, 30000.0);

#ifndef REFLECTION_GLOBAL
    return reflection; 
#endif

    // 3. 计算反射方向
    vec3 offsetViewPos = viewPos + mat3(gbufferModelView) * worldNormal * saturate(length(viewPos) * 3e-4);
    vec3 reflectWorldDir = reflect(worldDir, worldNormal);
    if (dot(worldNormal, reflectWorldDir) < EPS) return reflection;

#ifdef ROUGH_REFLECTIONS
    vec3 finalReflectDir = reflectWorldDir;
    if (material.isRough) {
        mat3 tbnMatrix = BuildOrthonormalBasis(worldNormal);
        vec2 noise = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter + 3);
        vec3 halfway = tbnMatrix * SampleGGXVNDF(-worldDir * tbnMatrix, material.roughness, noise);
        finalReflectDir = reflect(worldDir, halfway);
        if (dot(worldNormal, finalReflectDir) < EPS) return reflection;
    }
#else
    vec3 finalReflectDir = reflectWorldDir;
#endif

    // 4. 静态天空反射阶段
#ifdef REFLECTION_SKY
    if (skylight > EPS && isEyeInWater == 0) {
        vec3 skyRadiance = textureBicubic(skyMapTex, saturate(ProjectSky(finalReflectDir))).rgb;
        vec3 skyColor = skyRadiance * smoothstep(0.3, 0.7, skylight);
        
        // 天空反射也要经过区间限制，防止过曝
        skyColor = min(skyColor, vec3(REF_MAX));
        
        reflection.rgb = max(reflection.rgb, skyColor); 
    }
#endif

    // 5. 屏幕空间反射 (SSR) 阶段
#ifdef REFLECTION_SCREEN_SPACE
    uint maxSamples = uint(LIGHT_REFLECTION_SAMPLES * (material.isRough ? oms(material.roughness) : 1.0));
    
    if (ScreenSpaceRaytrace(offsetViewPos, mat3(gbufferModelView) * finalReflectDir, dither, maxSamples, screenPos)) {
        float edgeFade = screenPos.x * screenPos.y * oms(screenPos.x) * oms(screenPos.y);
        edgeFade = saturate(edgeFade * 50.0); 
        
        vec3 ssrColor = texture(colortex4, screenPos.xy * 0.5).rgb;
        
        // 同样对 SSR 结果进行亮度锁定，防止那种“不可名状的 Bug”
        ssrColor = min(ssrColor, vec3(REF_MAX + 0.2)); 
        
        reflection.rgb = mix(reflection.rgb, ssrColor, edgeFade);

        ivec2 texel = uvToTexel(screenPos.xy);
        vec3 reflectViewPos = ScreenToViewPos(vec3(screenPos.xy, loadDepth0(texel)));
        reflection.a = distance(reflectViewPos, viewPos);
    }
#endif

    return reflection;
}