// Adapted from "Screen Space sBitMask Lighting with Visibility Bitmask" by Olivier Therrien, et al.
// https://arxiv.org/pdf/2301.11376
// https://cdrinmatane.github.io/posts/cgspotlight-slides/
// https://cybereality.com/screen-space-indirect-lighting-with-visibility-bitmask-improvement-to-gtao-ssao-real-time-ambient-occlusion-algorithm-glsl-shader-implementation/

//================================================================================================//

#define SSILVB_SLICE_COUNT 1 // [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16]
#define SSILVB_SAMPLE_COUNT 32 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60 62 64]
#define SSILVB_SECTOR_COUNT 32 // [4 8 16 32 64 128]
#define SSILVB_HIT_THICKNESS 1.0 // [0.25 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0]

// ====== 调节 GI 亮度的选项 ======
#ifndef SSILVB_GI_BRIGHTNESS
    #define SSILVB_GI_BRIGHTNESS 1.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0]
#endif

// 手部排除阈值
#ifndef SSILVB_HAND_DEPTH_THRESHOLD
    #define SSILVB_HAND_DEPTH_THRESHOLD 0.56 // [0.0 0.1 0.2 0.3 0.4 0.5 0.56 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#endif

// ====== GI 渲染距离控制 ======
#define SSILVB_DISTANCE_LIMIT
#define SSILVB_MAX_DISTANCE        64.0    // [16.0 32.0 48.0 64.0 96.0 128.0 256.0]
#define SSILVB_FADE_START_DISTANCE 48.0    // [8.0 16.0 32.0 48.0 64.0 80.0 112.0]

// ====== 方块光单独增强 ======
#ifndef SSILVB_BLOCKLIGHT_BOOST
    #define SSILVB_BLOCKLIGHT_BOOST 8.0 // [1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0]  单独提高从场景表面采样的间接光亮度
#endif

//================================================================================================//

#include "/lib/utility/ShaderFastMathLib.glsl"

// 快速复数乘法
vec2 cmul(vec2 c0, vec2 c1) {
    return vec2(c0.x * c1.x - c0.y * c1.y, c0.y * c1.x + c0.x * c1.y);
}

// ---- 数学工具函数 ----
float SamplePartialSlice(float x, float sin_thVN) {
    float abs_x = abs(x);
    if ((abs_x - 0.5) < 0.5) {
        float s = sin_thVN;
        float o = s - s * s;
        float slp0 = 1.0 / (1.0 + (PI  - 1.0) * (s - o * 0.30546));
        float slp1 = 1.0 / (1.0 - (1.0 - exp2(-20.0)) * (s + o * mix(0.5, 0.785, s)));
        float k = mix(0.1, 0.25, s);

        const float a = 1.0 - (PI - 2.0) / (PI - 1.0);
        const float b = 1.0 / (PI - 1.0);

        float d0 =   a - slp0 * b;
        float d1 = 1.0 - slp1;

        float f0 = d0 * (PI * abs_x - asinFast4(abs_x));
        float f1 = d1 * (abs_x - 1.0);

        float kk = k * k;
        float h0 = sqrt(f0 * f0 + kk) - k;
        float h1 = sqrt(f1 * f1 + kk) - k;
        float hh = (h0 * h1) / (h0 + h1);

        float y = abs_x - sqrt(hh * (hh + 2.0 * k));
        return signMul(y, x);
    }
    return x;
}

float ArcTan11(vec2 dir) {
    float x = abs(dir.x);
    float y =     dir.y;
    float u = 2.0 + x * (1.27324 + x * (-0.189431 + (0.08204 - 0.0242564 * x) * x));
    float f = y / u;
    if (dir.x < 0.0) f = signI(dir.y) - f;
    return f;
}

vec2 SamplePartialSliceDir(vec3 vvsN, vec2 dir0) {
    float l = sdot(vvsN.xy);
    if (l > 0.0) {
        float rl = inversesqrt(l);
        vec2 n = vvsN.xy * rl;
        dir0 = cmul(dir0, n * vec2(1.0, -1.0));

        float x = ArcTan11(dir0);
        float ang = SamplePartialSlice(x, l * rl) * PI;

        vec2 dir = vec2(cos(ang), sin(ang));
        return cmul(dir, n);
    }
    return dir0;
}

vec4 GetQuaternion(vec3 from, vec3 to) {
    vec3 xyz = cross(from, to);
    float s  =   dot(from, to);
    float u = inversesqrt(saturate(s * 0.5 + 0.5));
    s    = 1.0 / u;
    xyz *= u * 0.5;
    return vec4(xyz, s);
}

vec4 GetQuaternion(vec3 to) {
    vec3 xyz = vec3(-to.y, to.x, 0.0);
    float s  =                   to.z;
    float u = inversesqrt(saturate(s * 0.5 + 0.5));
    s    = 1.0 / u;
    xyz *= u * 0.5;
    return vec4(xyz, s);
}

vec3 Transform_Qz0(vec3 v, vec4 q) {
    float k = v.y * q.x - v.x * q.y;
    float g = 2.0 * (v.z * q.w + k);
    vec3 r;
    r.xy = v.xy + q.yx * vec2(g, -g);
    r.z  = v.z  + 2.0 * (q.w * k - v.z * dot(q.xy, q.xy));
    return r;
}

vec3 Transform_Vz0Qz0(vec2 v, vec4 q) {
    float o = q.x * v.y;
    float c = q.y * v.x;
    vec3 b = vec3( o - c, -o + c, o - c);
    return vec3(v, 0.0) + 2.0 * (b * q.yxw);
}

vec2 SliceRelCDF_Cos(vec2 x, float angN, float sinN) {
    vec2 phi = x * TAU - PI;
    return -cos(angN - phi) - phi * sinN;
}

const uint sectorCount = SSILVB_SECTOR_COUNT;
uint updateSectors(vec2 horizon) {
    uint startBit = uint(horizon.x * float(sectorCount));
    uint horizonAngle = uint(ceil((horizon.y - horizon.x) * float(sectorCount)));
    uint angleBit = horizonAngle > 0u ? uint(0xFFFFFFFFu >> (sectorCount - horizonAngle)) : 0u;
    return angleBit << startBit;
}

//================================================================================================//

vec4 CalculateSSILVB(vec2 fragCoord, vec3 viewPos, vec3 worldNormal, float skylight) {
    const int sliceCount = SSILVB_SLICE_COUNT;
    const int sampleCount = SSILVB_SAMPLE_COUNT;
    const float hitThickness = SSILVB_HIT_THICKNESS * 0.1;

    const float rSliceCount = 1.0 / float(sliceCount);
    const float rSampleCount = 1.0 / float(sampleCount);

    // 天空光照预计算
    vec3 skyIrradiance = ConvolvedReconstructSH3(global.skySH, worldNormal) * cube(skylight);

    // 距离限制
    #ifdef SSILVB_DISTANCE_LIMIT
        float pixDist = length(viewPos);
        if (pixDist > SSILVB_MAX_DISTANCE) {
            return vec4(skyIrradiance * SSILVB_GI_BRIGHTNESS, 1.0);
        }
    #endif

    #if defined LOD_MOD
        float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
    #else
        const float screenDepthSky = 1.0;
    #endif

    float dither = SampleStbnVec1(ivec2(gl_GlobalInvocationID.xy), frameCounter);

    vec3 viewDir = normalize(-viewPos);
    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

    vec3 viewDirOffset = viewDir * hitThickness;

    vec4 Q_toV = GetQuaternion(viewDir);
    vec4 Q_fromV = Q_toV * vec4(vec3(-1.0), 1.0);
    vec3 normalVVS = Transform_Qz0(viewNormal, Q_fromV);

    vec4 irradiance = vec4(0.0);

    for (int slice = 0; slice < sliceCount; ++slice) {
        vec2 dir = SampleStbnUnitvec2(ivec2(gl_GlobalInvocationID.xy), slice + frameCounter * sliceCount);
        dir = SamplePartialSliceDir(normalVVS, normalize(dir * 2.0 - 1.0));
        vec3 smplDirVS = Transform_Vz0Qz0(dir, Q_toV);

        vec3 sliceN = cross(viewDir, smplDirVS);
        vec3 projN = viewNormal - sliceN * dot(viewNormal, sliceN);

        float projNSqrLen = dot(projN, projN);
        if (projNSqrLen < EPS) continue;

        float cosN = dot(projN, viewDir) * inversesqrt(projNSqrLen);
        float angN = signMul(acosFast4(satSnorm(cosN)), dot(viewDir, cross(sliceN, projN)));
        float angOff = angN * rPI + 0.5;
        float sinN = sin(angN);

        float w0 = saturate((sinN / (cosN + angN * sinN)) * (PI / 4.0) + 0.5);
        float t1 = 0.25 / (cosN + angN * sinN);
        float t0 = (3.0 * cosN + (4.0 * angN + PI) * sinN) * t1;

        float w0_remap_mul = 1.0 / (1.0 - w0);
        float w0_remap_add = (t0 - w0) * w0_remap_mul;
        w0_remap_mul *= t1;

        vec2 rayDir = ViewToScreenPosRaw(smplDirVS * abs(viewPos.z) + viewPos).xy - fragCoord;
        rayDir *= minOf((step(0.0, rayDir) - fragCoord) / rayDir);

        float rayDirNorm = inversesqrt(sdot(rayDir * viewSize));
        float stepScale = -rSampleCount * log2(saturate(rayDirNorm));

        float stepLength = exp2(stepScale * dither);
        stepScale = exp2(stepScale);
        rayDir *= rayDirNorm;

        uint bitMask = 0u;

        for (uint samp = 0u; samp < sampleCount; ++samp) {
            vec2 sampleUV = fragCoord + rayDir * stepLength;
            stepLength *= stepScale;

            if (saturate(sampleUV) == sampleUV) {
                ivec2 sampleTexel = uvToTexel(sampleUV);
                float sampleDepth = loadDepth0(sampleTexel);

            #if defined LOD_MOD
                if (sampleDepth > 1.0 - EPS) sampleDepth = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth0Lod(sampleTexel)));
            #endif

                // 排除手部及过近物体
                if (sampleDepth > screenDepthSky - EPS || sampleDepth < SSILVB_HAND_DEPTH_THRESHOLD) continue;

                vec3 samplePos = ScreenToViewPos(vec3(sampleUV, sampleDepth));

                vec3 sampleDirFront = samplePos - viewPos;
                vec3 sampleDirBack = sampleDirFront + viewDirOffset * samplePos.z;

                vec2 frontBackHorizon = vec2(
                    fastRcpSqrtNR0(sdot(sampleDirFront)) * dot(sampleDirFront, viewDir),
                    fastRcpSqrtNR0(sdot(sampleDirBack)) * dot(sampleDirBack, viewDir)
                );

                frontBackHorizon = acosFast4(satSnorm(frontBackHorizon));
                frontBackHorizon = saturate(frontBackHorizon * rPI + angOff);

                // 映射到切片相对分布
                frontBackHorizon = SliceRelCDF_Cos(frontBackHorizon, angN, sinN);

                // 部分切片重映射
                frontBackHorizon = frontBackHorizon * w0_remap_mul + w0_remap_add;

                uint sBitMask = updateSectors(frontBackHorizon);
                uint sampleOccludedBit = sBitMask & ~bitMask;

                if (sampleOccludedBit > 0u) {
                    vec3 sampleRadiance = texelFetch(colortex4, sampleTexel >> 1, 0).rgb;
                    sampleRadiance = min(sampleRadiance, 512.0);
                    // 方块光单独增强
                    irradiance.rgb += float(bitCount(sampleOccludedBit)) * sampleRadiance * SSILVB_BLOCKLIGHT_BOOST;

                    bitMask |= sBitMask;
                }
            }
        }

        irradiance.a += float(bitCount(bitMask));
    }

    irradiance *= rSliceCount / float(sectorCount);

    // 距离淡出
    #ifdef SSILVB_DISTANCE_LIMIT
        float fadeFactor = saturate((SSILVB_MAX_DISTANCE - pixDist) / (SSILVB_MAX_DISTANCE - SSILVB_FADE_START_DISTANCE));
        irradiance.rgb *= fadeFactor;
        irradiance.a = mix(0.0, irradiance.a, fadeFactor);
    #endif

    irradiance = vec4(irradiance.rgb, saturate(1.0 - irradiance.a));
    irradiance.rgb += skyIrradiance * irradiance.a;
    irradiance.rgb *= SSILVB_GI_BRIGHTNESS;

    return irradiance;
}