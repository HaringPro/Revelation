// Adapted from "Screen Space sBitMask Lighting with Visibility Bitmask" by Olivier Therrien, et al.
// https://arxiv.org/pdf/2301.11376
// https://cdrinmatane.github.io/posts/cgspotlight-slides/
// https://cybereality.com/screen-space-indirect-lighting-with-visibility-bitmask-improvement-to-gtao-ssao-real-time-ambient-occlusion-algorithm-glsl-shader-implementation/

//================================================================================================//

#define SSILVB_SLICE_COUNT 1 // [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16]
#define SSILVB_SAMPLE_COUNT 32 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60 62 64]
#define SSILVB_SECTOR_COUNT 32 // [4 8 16 32 64 128]
#define SSILVB_HIT_THICKNESS 1.0 // [0.25 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0]

//================================================================================================//

#include "/lib/utility/ShaderFastMathLib.glsl"

// https://www.shadertoy.com/view/XcdBWf
// MIT License. Copyright (C) 2024 Mirko Salm.
vec2 cmul(vec2 c0, vec2 c1) {
    return vec2(c0.x * c1.x - c0.y * c1.y, c0.y * c1.x + c0.x * c1.y);
}

float SamplePartialSlice(float x, float sin_thVN) {
    float abs_x = abs(x);
    if (abs_x < EPS || abs_x >= 1.0) return x;

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

// https://www.shadertoy.com/view/lXBfWm
// dir: normalized vector | out: angle in radians [-Pi, Pi] (max abs error ~0.000000546448 rad)
float ArcTan(vec2 dir) {
    float x = abs(dir.x);
    float y =     dir.y;

    float u = 0.63662 + x * (0.405285 + x * (-0.0602976 + (0.0261141 - 0.00772104 * x) * x));// max abs err ~0.0000454545 rad

    float f = y / u;

    if (dir.x < 0.0) f = (dir.y < 0.0 ? -PI : PI) - f;

    return f;
}

float ArcTan11(vec2 dir) { // == ArcTan(dir) / Pi
    float x = abs(dir.x);
    float y =     dir.y;

    float u = 2.0 + x * (1.27324 + x * (-0.189431 + (0.08204 - 0.0242564 * x) * x));

    float f = y / u;

    if (dir.x < 0.0) f = signI(dir.y) - f;

    return f;
}

vec2 SamplePartialSliceDir(vec3 vvsN, vec2 dir0) {
    float l = sdot(vvsN.xy);
    if (l < EPS) return dir0;

    float rl = inversesqrt(l);
    vec2 n = vvsN.xy * rl;
    // align n with x-axis
    dir0 = cmul(dir0, n * vec2(1.0, -1.0));

    // sample slice angle
    float x = ArcTan11(dir0);
    float ang = SamplePartialSlice(x, l * rl) * PI;

    // ray space slice direction
    vec2 dir = vec2(cos(ang), sin(ang));

    // align x-axis with n
    return cmul(dir, n);
}

vec4 GetQuaternion(vec3 from, vec3 to) {
    vec3 xyz = cross(from, to);
    float s  =   dot(from, to);

    float u = inversesqrt(saturate(s * 0.5 + 0.5));// rcp(cosine half-angle formula)

    s    = 1.0 / u;
    xyz *= u * 0.5;

    return vec4(xyz, s);
}

vec4 GetQuaternion(vec3 to) {
    vec3 xyz = vec3(-to.y, to.x, 0.0);// cross(from, to);
    float s  =                   to.z;//   dot(from, to);

    float u = inversesqrt(saturate(s * 0.5 + 0.5));// rcp(cosine half-angle formula)

    s    = 1.0 / u;
    xyz *= u * 0.5;

    return vec4(xyz, s);
}

// transform v by unit quaternion q.xy0s
vec3 Transform_Qz0(vec3 v, vec4 q) {
    float k = v.y * q.x - v.x * q.y;
    float g = 2.0 * (v.z * q.w + k);

    vec3 r;
    r.xy = v.xy + q.yx * vec2(g, -g);
    r.z  = v.z  + 2.0 * (q.w * k - v.z * dot(q.xy, q.xy));

    return r;
}

// transform v.xy0 by unit quaternion q.xy0s
vec3 Transform_Vz0Qz0(vec2 v, vec4 q) {
    float o = q.x * v.y;
    float c = q.y * v.x;

    vec3 b = vec3( o - c,
                  -o + c,
                   o - c);

    return vec3(v, 0.0) + 2.0 * (b * q.yxw);
}

vec2 SliceRelCDF_Cos(vec2 x, float angN, float cosN) {
    vec2 phi = x * PI - hPI;

    vec2 t0 = 3.0 * cosN + -cos(angN - 2.0 * phi) + (4.0 * angN - 2.0 * phi + PI) * sin(angN);
    float t1 = 4.0 * (cosN + angN * sin(angN));

    return mix(x, t0 / t1, step(abs(x - 0.5), vec2(0.5)));
}

// https://cdrinmatane.github.io/posts/ssaovb-code/
const uint sectorCount = SSILVB_SECTOR_COUNT;
uint updateSectors(in vec2 horizon) {
    uint startBit = uint(horizon.x * float(sectorCount));

    uint horizonAngle = uint(ceil((horizon.y - horizon.x) * float(sectorCount)));
    uint angleBit = horizonAngle > 0u ? uint(0xFFFFFFFFu >> (sectorCount - horizonAngle)) : 0u;

    return angleBit << startBit;
}

//================================================================================================//

vec4 CalculateSSILVB(in vec2 fragCoord, in vec3 viewPos, in vec3 worldNormal, in float skylight) {
	const int sliceCount = SSILVB_SLICE_COUNT;
	const int sampleCount = SSILVB_SAMPLE_COUNT;
	const float hitThickness = SSILVB_HIT_THICKNESS * 0.1;

	const float rSliceCount = 1.0 / float(sliceCount);
	const float rSampleCount = 1.0 / float(sampleCount);

    float dither = SampleStbnVec1(ivec2(gl_GlobalInvocationID.xy), frameCounter);

    vec3 viewDir = normalize(-viewPos);
    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

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
        float cosN = dot(projN, viewDir) * inversesqrt(sdot(projN));

        float angN = signMul(acosFast4(satSnorm(cosN)), dot(viewDir, cross(sliceN, projN)));
        float angOff = angN * rPI + 0.5;

        // percentage of the slice we don't use ([0, angN]-integrated slice-relative pdf)
        float w0 = saturate((sin(angN) / (cos(angN) + angN * sin(angN))) * (PI / 4.0) + 0.5);

        // partial slice re-mapping constants
        float w0_remap_mul = 1.0 / (1.0 - w0);
        float w0_remap_add = -w0 * w0_remap_mul;

        vec2 rayDir = ViewToScreenSpace(smplDirVS + viewPos).xy - fragCoord;
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
                if (sampleDepth > 1.0 - EPS) continue;

                vec3 samplePos = ScreenToViewSpace(vec3(sampleUV, sampleDepth));
				vec3 sampleDiff = samplePos - viewPos;

                vec3 sampleDirFront = sampleDiff * fastRcpSqrtNR0(sdot(sampleDiff));
                vec3 sampleDirBack = sampleDiff - viewDir * max(abs(samplePos.z) * hitThickness, 0.25);

                vec2 frontBackHorizon = vec2(dot(sampleDirFront, viewDir),
                     fastRcpSqrtNR0(sdot(sampleDirBack)) * dot(sampleDirBack, viewDir));

                frontBackHorizon = acosFast4(satSnorm(frontBackHorizon));
                frontBackHorizon = saturate(frontBackHorizon * rPI + angOff);

                // map to slice relative distribution
                frontBackHorizon = SliceRelCDF_Cos(frontBackHorizon, angN, cosN);

                // partial slice re-mapping
                frontBackHorizon = frontBackHorizon * w0_remap_mul + w0_remap_add;

                uint sBitMask = updateSectors(frontBackHorizon);
                uint sampleOccludedBit = sBitMask & ~bitMask;

                if (sampleOccludedBit > 0u) {
                    // vec3 sampleNormal = mat3(gbufferModelView) * FetchSurfaceNormal(sampleTexel);

                    vec3 sampleRadiance = texelFetch(colortex4, sampleTexel >> 1, 0).rgb;
                    irradiance.rgb += float(bitCount(sampleOccludedBit)) *
                        // fastSqrtNR0(saturate(-dot(sampleNormal, sampleDirFront))) *
                        sampleRadiance;

                    bitMask |= sBitMask;
                }
			}
        }

        irradiance.a += float(bitCount(bitMask));
    }

    irradiance *= rSliceCount / float(sectorCount);
    irradiance = vec4(irradiance.rgb, saturate(1.0 - irradiance.a));

    vec3 skyIrradiance = ConvolvedReconstructSH3(global.light.skySH, worldNormal);
    irradiance.rgb += skyIrradiance * irradiance.a * cube(skylight);
    return irradiance;
}
