vec4 FsrEasuRF(vec2 p) {
    return vec4(textureGather(FSR1_EASU_IN, p, 0));
}
vec4 FsrEasuGF(vec2 p) {
    return vec4(textureGather(FSR1_EASU_IN, p, 1));
}
vec4 FsrEasuBF(vec2 p) {
    return vec4(textureGather(FSR1_EASU_IN, p, 2));
}

bool fsr1InBounds(uvec2 p, uvec2 sizeXY) {
    return p.x < sizeXY.x && p.y < sizeXY.y;
}

void FsrEasuCon(
    out uvec4 con0,
    out uvec4 con1,
    out uvec4 con2,
    out uvec4 con3,
    float inputViewportInPixelsX,
    float inputViewportInPixelsY,
    float inputSizeInPixelsX,
    float inputSizeInPixelsY,
    float outputSizeInPixelsX,
    float outputSizeInPixelsY)
{
    con0[0] = floatBitsToUint(inputViewportInPixelsX * (1 / outputSizeInPixelsX));
    con0[1] = floatBitsToUint(inputViewportInPixelsY * (1 / outputSizeInPixelsY));
    con0[2] = floatBitsToUint((0.5) * inputViewportInPixelsX * (1 / outputSizeInPixelsX) - (0.5));
    con0[3] = floatBitsToUint((0.5) * inputViewportInPixelsY * (1 / outputSizeInPixelsY) - (0.5));
    con1[0] = floatBitsToUint((1 / inputSizeInPixelsX));
    con1[1] = floatBitsToUint((1 / inputSizeInPixelsY));
    con1[2] = floatBitsToUint((1.0) * (1 / inputSizeInPixelsX));
    con1[3] = floatBitsToUint((-1.0) * (1 / inputSizeInPixelsY));
    con2[0] = floatBitsToUint((-1.0) * (1 / inputSizeInPixelsX));
    con2[1] = floatBitsToUint((2.0) * (1 / inputSizeInPixelsY));
    con2[2] = floatBitsToUint((1.0) * (1 / inputSizeInPixelsX));
    con2[3] = floatBitsToUint((2.0) * (1 / inputSizeInPixelsY));
    con3[0] = floatBitsToUint((0.0) * (1 / inputSizeInPixelsX));
    con3[1] = floatBitsToUint((4.0) * (1 / inputSizeInPixelsY));
    con3[2] = con3[3] = 0;
}

void FsrEasuTapF(
    inout vec3 aC,
    inout float aW,
    vec2 off,
    vec2 dir,
    vec2 len,
    float lob,
    float clp,
    vec3 c)
{
    vec2 v;
    v.x = (off.x * (dir.x)) + (off.y * dir.y);
    v.y = (off.x * (-dir.y)) + (off.y * dir.x);
    v *= len;
    float d2 = v.x * v.x + v.y * v.y;
    d2 = min(d2, clp);
    float wB = float(2.0 / 5.0) * d2 + float(-1.0);
    float wA = lob * d2 + float(-1.0);
    wB *= wB;
    wA *= wA;
    wB = float(25.0 / 16.0) * wB + float(-(25.0 / 16.0 - 1.0));
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

void FsrEasuSetF(
    inout vec2 dir,
    inout float len,
    vec2 pp,
    bool biS, bool biT, bool biU, bool biV,
    float lA, float lB, float lC, float lD, float lE)
{
    float w = float(0.0);
    if (biS) w = (float(1.0) - pp.x) * (float(1.0) - pp.y);
    if (biT) w = pp.x * (float(1.0) - pp.y);
    if (biU) w = (float(1.0) - pp.x) * pp.y;
    if (biV) w = pp.x * pp.y;
    float dc = lD - lC;
    float cb = lC - lB;
    float lenX = max(abs(dc), abs(cb));
    lenX = uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(lenX));
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
    lenX *= lenX;
    len += lenX * w;
    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(lenY));
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
    lenY *= lenY;
    len += lenY * w;
}

void FsrEasuF(
    out vec3 pix,
    uvec2 ip,
    uvec4 con0,
    uvec4 con1,
    uvec4 con2,
    uvec4 con3)
{
    vec2 pp = vec2(ip) * uintBitsToFloat(con0.xy) + uintBitsToFloat(con0.zw);
    vec2 fp = floor(pp);
    pp -= fp;
    vec2 p0 = fp * uintBitsToFloat(con1.xy) + uintBitsToFloat(con1.zw);
    vec2 p1 = p0 + uintBitsToFloat(con2.xy);
    vec2 p2 = p0 + uintBitsToFloat(con2.zw);
    vec2 p3 = p0 + uintBitsToFloat(con3.xy);
    vec4 bczzR = FsrEasuRF(p0);
    vec4 bczzG = FsrEasuGF(p0);
    vec4 bczzB = FsrEasuBF(p0);
    vec4 ijfeR = FsrEasuRF(p1);
    vec4 ijfeG = FsrEasuGF(p1);
    vec4 ijfeB = FsrEasuBF(p1);
    vec4 klhgR = FsrEasuRF(p2);
    vec4 klhgG = FsrEasuGF(p2);
    vec4 klhgB = FsrEasuBF(p2);
    vec4 zzonR = FsrEasuRF(p3);
    vec4 zzonG = FsrEasuGF(p3);
    vec4 zzonB = FsrEasuBF(p3);
    vec4 bczzL = bczzB * vec4(0.5) + (bczzR * vec4(0.5) + bczzG);
    vec4 ijfeL = ijfeB * vec4(0.5) + (ijfeR * vec4(0.5) + ijfeG);
    vec4 klhgL = klhgB * vec4(0.5) + (klhgR * vec4(0.5) + klhgG);
    vec4 zzonL = zzonB * vec4(0.5) + (zzonR * vec4(0.5) + zzonG);
    float bL = bczzL.x;
    float cL = bczzL.y;
    float iL = ijfeL.x;
    float jL = ijfeL.y;
    float fL = ijfeL.z;
    float eL = ijfeL.w;
    float kL = klhgL.x;
    float lL = klhgL.y;
    float hL = klhgL.z;
    float gL = klhgL.w;
    float oL = zzonL.z;
    float nL = zzonL.w;
    vec2 dir = vec2(0.0);
    float len = float(0.0);
    FsrEasuSetF(dir, len, pp, true, false, false, false, bL, eL, fL, gL, jL);
    FsrEasuSetF(dir, len, pp, false, true, false, false, cL, fL, gL, hL, kL);
    FsrEasuSetF(dir, len, pp, false, false, true, false, fL, iL, jL, kL, nL);
    FsrEasuSetF(dir, len, pp, false, false, false, true, gL, jL, kL, lL, oL);
    vec2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool zro = dirR < float(1.0 / 32768.0);
    dirR = uintBitsToFloat(0x5f347d74u - (floatBitsToUint(dirR) >> 1u));
    dirR = zro ? float(1.0) : dirR;
    dir.x = zro ? float(1.0) : dir.x;
    dir *= vec2(dirR);
    len = len * float(0.5);
    len *= len;
    float stretch = (dir.x * dir.x + dir.y * dir.y) * (uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint((max(abs(dir.x), abs(dir.y))))));
    vec2 len2 = vec2(float(1.0) + (stretch - float(1.0)) * len, float(1.0) + float(-0.5) * len);
    float lob = float(0.5) + float((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(lob));

    vec3 min4 = min(
            min(vec3(ijfeR.z, ijfeG.z, ijfeB.z),
                min(vec3(klhgR.w, klhgG.w, klhgB.w),
                    vec3(ijfeR.y, ijfeG.y, ijfeB.y))),
            vec3(klhgR.x, klhgG.x, klhgB.x)
        );
    vec3 max4 = max(
            max(
                vec3(ijfeR.z, ijfeG.z, ijfeB.z),
                max(vec3(klhgR.w, klhgG.w, klhgB.w),
                    vec3(ijfeR.y, ijfeG.y, ijfeB.y))
            ),
            vec3(klhgR.x, klhgG.x, klhgB.x)
        );
    vec3 aC = vec3(0.0);
    float aW = float(0.0);
    FsrEasuTapF(aC, aW, vec2(0.0, -1.0) - pp, dir, len2, lob, clp, vec3(bczzR.x, bczzG.x, bczzB.x)); // b
    FsrEasuTapF(aC, aW, vec2(1.0, -1.0) - pp, dir, len2, lob, clp, vec3(bczzR.y, bczzG.y, bczzB.y)); // c
    FsrEasuTapF(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, vec3(ijfeR.x, ijfeG.x, ijfeB.x)); // i
    FsrEasuTapF(aC, aW, vec2(0.0, 1.0) - pp, dir, len2, lob, clp, vec3(ijfeR.y, ijfeG.y, ijfeB.y)); // j
    FsrEasuTapF(aC, aW, vec2(0.0, 0.0) - pp, dir, len2, lob, clp, vec3(ijfeR.z, ijfeG.z, ijfeB.z)); // f
    FsrEasuTapF(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, vec3(ijfeR.w, ijfeG.w, ijfeB.w)); // e
    FsrEasuTapF(aC, aW, vec2(1.0, 1.0) - pp, dir, len2, lob, clp, vec3(klhgR.x, klhgG.x, klhgB.x)); // k
    FsrEasuTapF(aC, aW, vec2(2.0, 1.0) - pp, dir, len2, lob, clp, vec3(klhgR.y, klhgG.y, klhgB.y)); // l
    FsrEasuTapF(aC, aW, vec2(2.0, 0.0) - pp, dir, len2, lob, clp, vec3(klhgR.z, klhgG.z, klhgB.z)); // h
    FsrEasuTapF(aC, aW, vec2(1.0, 0.0) - pp, dir, len2, lob, clp, vec3(klhgR.w, klhgG.w, klhgB.w)); // g
    FsrEasuTapF(aC, aW, vec2(1.0, 2.0) - pp, dir, len2, lob, clp, vec3(zzonR.z, zzonG.z, zzonB.z)); // o
    FsrEasuTapF(aC, aW, vec2(0.0, 2.0) - pp, dir, len2, lob, clp, vec3(zzonR.w, zzonG.w, zzonB.w)); // n
    pix = min(max4, max(min4, aC * vec3((1.0 / aW))));
}

shared uvec4 g_Fsr1EasuConsts[4];

void fsr1Easu(
    vec2 renderViewportSize,
    vec2 containerTextureSize,
    vec2 upscaledViewportSize
) {
    if (gl_LocalInvocationID.x == 0 && gl_LocalInvocationID.y == 0) {
        uvec4 const0, const1, const2, const3;
        FsrEasuCon(const0, const1, const2, const3,
            renderViewportSize.x,
            renderViewportSize.y,
            containerTextureSize.x,
            containerTextureSize.y,
            upscaledViewportSize.x,
            upscaledViewportSize.y);
        g_Fsr1EasuConsts[0] = const0;
        g_Fsr1EasuConsts[1] = const1;
        g_Fsr1EasuConsts[2] = const2;
        g_Fsr1EasuConsts[3] = const3;
    }
    barrier();

    uvec2 sizeXY = uvec2(imageSize(FSR1_EASU_OUT));
    uvec2 gxy = gl_GlobalInvocationID.xy;

    if (fsr1InBounds(gxy, sizeXY)) {
        vec3 gamma2Color = vec3(0.0);
        FsrEasuF(gamma2Color, gxy, g_Fsr1EasuConsts[0], g_Fsr1EasuConsts[1], g_Fsr1EasuConsts[2], g_Fsr1EasuConsts[3]);
        imageStore(FSR1_EASU_OUT, ivec2(gxy), vec4(gamma2Color, 1.0));
    }
}
