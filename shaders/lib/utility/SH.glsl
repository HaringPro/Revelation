// https://www.gdcvault.com/play/273/Stupid-Spherical-Harmonics-(SH)
// https://dl.acm.org/doi/10.1145/3015459
// https://doi.org/10.1145/3478513.3480563

// ========== 方向性亮度控制（按需启用） ==========
#define SH_DIRECTIONAL_BRIGHTNESS_ENABLED   // 取消注释即可启用

// 六个面的亮度倍率（1.0 = 原始亮度）
#define SH_BRIGHTNESS_UP      1.0   // +Y 天空
#define SH_BRIGHTNESS_DOWN    1.0   // -Y 地面
#define SH_BRIGHTNESS_NORTH   1.0   // -Z 后方
#define SH_BRIGHTNESS_SOUTH   1.0   // +Z 前方
#define SH_BRIGHTNESS_EAST    1.0   // +X 右侧
#define SH_BRIGHTNESS_WEST    1.0   // -X 左侧

// 根据方向计算六面混合亮度因子
float GetDirectionalBrightness(in vec3 dir) {
    float factor = 1.0;
    factor *= mix(SH_BRIGHTNESS_DOWN, SH_BRIGHTNESS_UP, step(0.0, dir.y));
    factor *= mix(SH_BRIGHTNESS_NORTH, SH_BRIGHTNESS_SOUTH, step(0.0, dir.z));
    factor *= mix(SH_BRIGHTNESS_WEST, SH_BRIGHTNESS_EAST, step(0.0, dir.x));
    return factor;
}

// ========== 原始 SH 函数（无数学改动） ==========

float BasisSH1() {
    return sqrt(1.0 / (4.0 * PI));
}

float[4] BasisSH2(in vec3 dir) {
    return float[4](
        sqrt(1.0 / (4.0 * PI)),
        sqrt(3.0 / (4.0 * PI)) * dir.y,
        sqrt(3.0 / (4.0 * PI)) * dir.z,
        sqrt(3.0 / (4.0 * PI)) * dir.x
    );
}

float[9] BasisSH3(in vec3 dir) {
    return float[9](
        sqrt(1.0 / (4.0 * PI)),
        sqrt(3.0 / (4.0 * PI)) * dir.y,
        sqrt(3.0 / (4.0 * PI)) * dir.z,
        sqrt(3.0 / (4.0 * PI)) * dir.x,
        sqrt(15.0 / (4.0 * PI)) * dir.x * dir.y,
        sqrt(15.0 / (4.0 * PI)) * dir.y * dir.z,
        sqrt(5.0 / (16.0 * PI)) * (3.0 * dir.z * dir.z - 1.0),
        sqrt(15.0 / (4.0 * PI)) * dir.x * dir.z,
        sqrt(15.0 / (16.0 * PI)) * (dir.x * dir.x - dir.y * dir.y)
    );
}

vec3 ReconstructSH2(in vec3[4] coeff, in vec3 dir) {
    float[4] basis = BasisSH2(dir);

    vec3 color = coeff[0] * basis[0]
               + coeff[1] * basis[1]
               + coeff[2] * basis[2]
               + coeff[3] * basis[3];

    #ifdef SH_DIRECTIONAL_BRIGHTNESS_ENABLED
        color *= GetDirectionalBrightness(dir);
    #endif
    return color;
}

vec3 ReconstructSH3(in vec3[9] coeff, in vec3 dir) {
    float[9] basis = BasisSH3(dir);

    vec3 color = coeff[0] * basis[0]
               + coeff[1] * basis[1]
               + coeff[2] * basis[2]
               + coeff[3] * basis[3]
               + coeff[4] * basis[4]
               + coeff[5] * basis[5]
               + coeff[6] * basis[6]
               + coeff[7] * basis[7]
               + coeff[8] * basis[8];

    #ifdef SH_DIRECTIONAL_BRIGHTNESS_ENABLED
        color *= GetDirectionalBrightness(dir);
    #endif
    return color;
}

vec3 ConvolvedReconstructSH3(in vec3[9] coeff, in vec3 dir) {
    float[9] basis = BasisSH3(dir);
    const vec3 zh = vec3(sqrt(PI / 4.0), sqrt(PI / 3.0), sqrt((5.0 / 64.0) * PI));
    const vec3 kernel = zh * sqrt(4.0 * PI / vec3(1.0, 3.0, 5.0)) / PI;

    vec3 color = coeff[0] * basis[0] * kernel.x
               + coeff[1] * basis[1] * kernel.y
               + coeff[2] * basis[2] * kernel.y
               + coeff[3] * basis[3] * kernel.y
               + coeff[4] * basis[4] * kernel.z
               + coeff[5] * basis[5] * kernel.z
               + coeff[6] * basis[6] * kernel.z
               + coeff[7] * basis[7] * kernel.z
               + coeff[8] * basis[8] * kernel.z;

    #ifdef SH_DIRECTIONAL_BRIGHTNESS_ENABLED
        color *= GetDirectionalBrightness(dir);
    #endif
    return color;
}

struct AdhocSH2 {
    vec4 coeff;
    vec2 chroma;
};

AdhocSH2 InitAdhocSH2() {
    return AdhocSH2(vec4(0.0), vec2(0.0));
}

void AddAdhocSH2(inout AdhocSH2 a, in AdhocSH2 b) {
    a.coeff += b.coeff;
    a.chroma += b.chroma;
}

void MulAdhocSH2(inout AdhocSH2 a, in float b) {
    a.coeff *= b;
    a.chroma *= b;
}

void DivAdhocSH2(inout AdhocSH2 a, in float b) {
    a.coeff /= b;
    a.chroma /= b;
}

AdhocSH2 MixAdhocSH2(in AdhocSH2 a, in AdhocSH2 b, in float t) {
    return AdhocSH2(mix(a.coeff, b.coeff, t), mix(a.chroma, b.chroma, t));
}

vec3 SHToIrradiance(AdhocSH2 sh, in vec3 dir) {
    float L = dot(sh.coeff.yzw, dir) * rcp(sh.coeff.x + EPS);
    L = L * sqrt(1.0 / 3.0) + sqrt(1.0 / 4.0);

    vec3 irradiance = YCoCgToRGB(vec3(sqrt(4.0 * PI) * sh.coeff.x, sh.chroma));
    vec3 color = max0(irradiance * L);

    #ifdef SH_DIRECTIONAL_BRIGHTNESS_ENABLED
        color *= GetDirectionalBrightness(dir);
    #endif
    return color;
}

AdhocSH2 IrradianceToSH(in vec3 irradiance, in vec3 dir) {
    vec3 YCoCg = RGBToYCoCg(irradiance);

    AdhocSH2 sh;
    sh.coeff.x = sqrt(1.0 / (4.0 * PI)) * YCoCg.x;
    sh.coeff.yzw = sqrt(3.0 / (4.0 * PI)) * YCoCg.x * dir;
    sh.chroma = YCoCg.yz;

    return sh;
}