//================================================================================================//
// SVGF Upscale Diffuse Indirect (with quality & blur radius control)
//================================================================================================//
#if defined PASS_DEFERRED_LIGHTING
#if defined SSILVB_ENABLED && defined SVGF_ENABLED

// ========== 可调节参数 ==========
#ifndef SVGF_QUALITY
    #define SVGF_QUALITY 0 // [0 1 2]     // 0=仅自身, 1=十字形(4样本), 2=完整3x3(8样本)
#endif
#ifndef SVGF_BLUR_RADIUS
    #define SVGF_BLUR_RADIUS 15.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 1.0 15.0 20.0 25.0 30.0 50.0] 采样半径倍数（1.0=原始相邻像素，>1.0扩大模糊范围）
#endif
// ================================

vec3 UpscaleDiffuseIndirect(in ivec2 texelPos, in vec3 worldNormal, in float viewDistance, in float NdotV) {
    texelPos >>= 1;
    ivec2 texelEnd = ivec2(halfViewEnd) - 1;

    vec3 sum = texelFetch(colortex3, texelPos, 0).rgb;
    float sumWeight = 1.0;

    #if SVGF_QUALITY == 0
        return sum;
    #endif

    float sigmaZ = -4.0 * NdotV;
    float depthCenter = viewDistance;

    // 计算缩放后的偏移量（模糊半径）
    float radius = max(1.0, SVGF_BLUR_RADIUS);
    ivec2 offsetScale = ivec2(round(radius));

    #if SVGF_QUALITY == 1
        // 十字形采样（4个方向）
        const ivec2 offsets[4] = ivec2[](ivec2(1,0), ivec2(-1,0), ivec2(0,1), ivec2(0,-1));
        for (int i = 0; i < 4; ++i) {
            ivec2 sampleTexel = clamp(texelPos + offsets[i] * offsetScale, ivec2(1), texelEnd);
            vec3 sampleAux = texelFetch(colortex14, sampleTexel, 0).rgb;
            float ndot = saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal));
            float weight = ndot * ndot;               // 平方代替 pow16
            float depthDiff = abs(sampleAux.z - depthCenter);
            weight *= exp2(depthDiff * sigmaZ);
            if (weight < 0.001) continue;
            vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;
            sum += sampleLight * weight;
            sumWeight += weight;
        }
    #else
        // 完整3x3采样（8个邻居）
        for (uint i = 0u; i < 8u; ++i) {
            ivec2 sampleTexel = clamp(texelPos + offset3x3N[i] * offsetScale, ivec2(1), texelEnd);
            vec3 sampleAux = texelFetch(colortex14, sampleTexel, 0).rgb;
            float ndot = saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal));
            float weight = ndot * ndot;
            weight = weight * weight;                 // ndot^4 (接近原始pow16)
            float depthDiff = abs(sampleAux.z - depthCenter);
            weight *= exp2(depthDiff * sigmaZ);
            if (weight < 0.001) continue;
            vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;
            sum += sampleLight * weight;
            sumWeight += weight;
        }
    #endif

    return sum * rcp(sumWeight);
}
#endif
#endif

//================================================================================================//
// Volumetric Fog Upscale (original logic, unchanged)
//================================================================================================//
#if defined PASS_COMPOSITE
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG

mat2x3 UnpackFogData(in uvec2 data) {
    return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
}

mat2x3 UpscaleVolumetricFog(in ivec2 texelPos, in float linearDepth) {
    ivec2 randTexel = ivec2(vec2(texelPos >> 1) + BlueNoise(texelPos, frameCounter + 7));
    float sigmaZ = -64.0 / linearDepth;

    mat2x3 sum = UnpackFogData(texelFetch(colortex11, randTexel, 0).xy);
    float sumWeight = 1.0;

    for (uint i = 0u; i < 8u; ++i) {
        ivec2 sampleTexel = randTexel + offset3x3N[i];
        uvec3 sampleFogData = texelFetch(colortex11, sampleTexel, 0).xyz;

        float sampleDepth = uintBitsToFloat(sampleFogData.z);
        float weight = exp2(abs(sampleDepth - linearDepth) * sigmaZ);

        sum += UnpackFogData(sampleFogData.xy) * weight;
        sumWeight += weight;
    }

    sum *= rcp(sumWeight);
    return sum;
}
#endif
#endif