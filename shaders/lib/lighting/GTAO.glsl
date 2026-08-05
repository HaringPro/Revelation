/* Ground-Truth Ambient Occlusion */
// Reference: https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf

#define GTAO_SLICES	2 // [1 2 3 4 5 6 8 10 12 15 17 20]
#define GTAO_DIRECTION_SAMPLES 4 // [1 2 3 4 5 6 8 10 12 15 17 20]

#define GTAO_RADIUS 2.0 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]
#define GTAO_INTENSITY 1.5 // [0.5 0.8 1.0 1.2 1.5 2.0 2.5 3.0]
// 在外部预先获取视线射线 (用于优化 ScreenToViewPos)
// vec3 viewRay = normalize(viewPos) * (abs(viewPos.z) / depth); 或类似实现

void SampleHorizonCosOptimized(
    in vec2 coord, 
    in vec2 offset, 
    in vec3 viewPos, 
    in vec3 viewDir, 
    in vec2 falloff, 
    in float rFalloffDiff, 
    inout vec2 cHorizonCos
) {
    vec2 uvPos = coord + offset;
    vec2 uvNeg = coord - offset;

    // 向量化纹理抓取，增加显存读取的连续性
    float dPos = loadDepth0(uvToTexel(uvPos));
    float dNeg = loadDepth0(uvToTexel(uvNeg));

    // Early-out：如果两侧都在第一人称手臂/极近距离内，直接跳过计算
    if (dPos < 0.56 && dNeg < 0.56) return;

    vec3 posV, negV;

    #if defined LOD_MOD
        // 展平分支，提取条件判断
        bool lodPos = dPos > (1.0 - EPS);
        bool lodNeg = dNeg > (1.0 - EPS);

        dPos = lodPos ? loadDepth0Lod(uvToTexel(uvPos)) : dPos;
        dNeg = lodNeg ? loadDepth0Lod(uvToTexel(uvNeg)) : dNeg;

        posV = (lodPos ? ScreenToViewPosLod(vec3(uvPos, dPos)) : ScreenToViewPos(vec3(uvPos, dPos))) - viewPos;
        negV = (lodNeg ? ScreenToViewPosLod(vec3(uvNeg, dNeg)) : ScreenToViewPos(vec3(uvNeg, dNeg))) - viewPos;
    #else
        // 理想情况下，如果你有 viewRay，这里应优化为：posV = viewRayPos * linearDepth - viewPos;
        posV = ScreenToViewPos(vec3(uvPos, dPos)) - viewPos;
        negV = ScreenToViewPos(vec3(uvNeg, dNeg)) - viewPos;
    #endif

    // 计算平方长度
    vec2 sqrLen = vec2(sdot(posV), sdot(negV));
    vec2 invNorm = inversesqrt(sqrLen);

    // 计算原始 Cos
    vec2 sHorizonCos = vec2(
        dot(posV, viewDir) * invNorm.x,
        dot(negV, viewDir) * invNorm.y
    );

    // Falloff 计算向量化
    vec2 weight = saturate((sqrLen - falloff.x) * rFalloffDiff);
    
    // Mix 并更新最大 Cos 值
    sHorizonCos = mix(sHorizonCos, cHorizonCos, weight);
    
    // 如果原始深度小于 0.56，强制当前端使用旧值 (修复跳出逻辑造成的单侧遮蔽)
    cHorizonCos.x = dPos < 0.56 ? cHorizonCos.x : max(sHorizonCos.x, cHorizonCos.x);
    cHorizonCos.y = dNeg < 0.56 ? cHorizonCos.y : max(sHorizonCos.y, cHorizonCos.y);
}

float CalculateGTAO(in vec2 coord, in vec3 viewPos, in vec3 normal, in vec2 dither) {
    float viewDistance = sdot(viewPos);
    float norm = inversesqrt(viewDistance);
    viewDistance *= norm;

    vec3 viewDir = viewPos * -norm;

    const float rSliceCount = 1.0 / float(GTAO_SLICES);
    const float rSampleCount = 1.0 / float(GTAO_DIRECTION_SAMPLES);

    // 预计算旋转矩阵和角度
    float sliceAngle = PI * rSliceCount;
    float startPhi = dither.x * sliceAngle;
    vec2 sliceDir = vec2(cos(startPhi), sin(startPhi));
    vec2 rotCosSin = vec2(cos(sliceAngle), sin(sliceAngle));
    mat2 rotMat = mat2(rotCosSin.x, rotCosSin.y, -rotCosSin.y, rotCosSin.x);

    float radius = GTAO_RADIUS * saturate(0.25 + viewDistance * rcp(64.0));
    vec2 sRadius = rSampleCount * radius * norm * diagonal2(gbufferProjection);
    vec2 falloff = sqr(radius * vec2(1.0, 4.0));
    float rFalloffDiff = 1.0 / (falloff.y - falloff.x);

    float visibility = 0.0;

    #pragma unroll
    for (uint slice = 0u; slice < GTAO_SLICES; ++slice) {
        vec3 directionV = vec3(sliceDir, 0.0);
        vec3 orthoDirectionV = directionV - dot(directionV, viewDir) * viewDir;
        vec3 axisV = cross(directionV, viewDir);
        vec3 projNormalV = normal - axisV * dot(normal, axisV);

        float lenV = sdot(projNormalV);
        float normV = inversesqrt(lenV);
        lenV *= normV;

        float sgnN = signI(dot(orthoDirectionV, projNormalV));
        float cosN = saturate(dot(projNormalV, viewDir) * normV);
        float n = sgnN * fastAcos(cosN);
        float sinN = sgnN * sqrt(saturate(1.0 - cosN * cosN));

        vec2 cHorizonCos = vec2(-1.0);
        vec2 stepDir = sliceDir * sRadius;
        vec2 offset = stepDir * dither.y;

        #pragma unroll
        for (uint samp = 0u; samp < GTAO_DIRECTION_SAMPLES; ++samp) {
            // 一次调用处理正反两个方向，减少循环开销
            SampleHorizonCosOptimized(coord, offset, viewPos, viewDir, falloff, rFalloffDiff, cHorizonCos);
            offset += stepDir;
        }

        vec2 h = n + clamp(vec2(fastAcos(cHorizonCos.x), -fastAcos(cHorizonCos.y)) - n, -hPI, hPI);
        h = cosN + 2.0 * h * sinN - cos(2.0 * h - n);

        visibility += lenV * (h.x + h.y);
        sliceDir = rotMat * sliceDir;
    }

    float ao = 0.25 * rSliceCount * visibility;
    return pow(saturate(ao), GTAO_INTENSITY);
}
//================================================================================================//
vec3 ApproxMultiBounce(in float ao, in vec3 albedo) {
	vec3 a = 2.0404 * albedo - 0.3324;
	vec3 b = 4.7951 * albedo - 0.6417;
	vec3 c = 2.7552 * albedo + 0.6903;

	return max(vec3(ao), ((ao * a - b) * ao + c) * ao);
}