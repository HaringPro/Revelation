/* Screen-Space Ambient Occlusion */

#define SSAO_SAMPLES 4 // [1 2 3 4 5 6 7 8 9 10 12 16 18 20 22 24 26 28 30 32 48 64]
#define SSAO_STRENGTH 1.2 // [0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

// 开关：是否在远景（LOD）区块内渲染 SSAO
// 【性能提示】保持注释状态可关闭远景 SSAO，能大幅提升面对大范围远景时的游戏帧率。
// #define SSAO_LOD_ENABLED 

//================================================================================================//

float CalculateSSAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in vec2 dir) {
    float viewPosZ = viewPos.z;
    float rSteps = 1.0 / float(SSAO_SAMPLES);
    float maxSqLen = viewPosZ * viewPosZ * 0.25;              // sqr(viewPosZ) * 0.25
    float rMaxSqLen = 1.0 / maxSqLen;
    float invViewPosZ = 1.0 / viewPosZ;
    vec2 rayStep = diagonal2(gbufferProjection) * ( -rSteps * invViewPosZ );

    const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle),
                                   sin(goldenAngle),  cos(goldenAngle));

    vec2 radius = vec2(0.0);
    float sum = 0.0;

    #pragma unroll
    for (uint i = 0u; i < SSAO_SAMPLES; ++i, dir *= goldenRotate) {
        radius += rayStep;
        vec2 sampleCoord = coord + dir * radius;
        ivec2 sampleTexel = uvToTexel(sampleCoord);
        float sampleDepth = loadDepth0(sampleTexel);
        if (sampleDepth < 0.56) continue;

        #if defined LOD_MOD
            if (sampleDepth > 1.0 - EPS) {
                #ifdef SSAO_LOD_ENABLED
                    sampleDepth = loadDepth0Lod(sampleTexel);
                #else
                    continue;
                #endif
            }
        #endif

        vec3 difference = ScreenToViewPos(vec3(sampleCoord, sampleDepth)) - viewPos;
        float diffSqLen = dot(difference, difference);

        if (diffSqLen > EPS && diffSqLen < maxSqLen) {
            float invLen = inversesqrt(diffSqLen);                     // 硬件快速倒数平方根
            float cosAngle = saturate(dot(normal, difference) * invLen);
            float weight = saturate(1.0 - diffSqLen * rMaxSqLen);
            sum += cosAngle * weight;
        }
    }

    float ao = 1.0 - sum * rSteps * SSAO_STRENGTH;
    ao = saturate(ao);
    return ao * ao;   // 等价于 sqr(saturate(ao))，但少一次函数调用
}