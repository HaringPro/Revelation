#define A_GPU 1
#define A_GLSL 1

#include "/ffx/fsr1/ffx_a.glsl"

#if FSR_EASU == 1
#define FSR_EASU_F 1
AF4 FsrEasuRF(AF2 p) { return AF4(textureGather(FSR1_EASU_IN, p, 0)); }
AF4 FsrEasuGF(AF2 p) { return AF4(textureGather(FSR1_EASU_IN, p, 1)); }
AF4 FsrEasuBF(AF2 p) { return AF4(textureGather(FSR1_EASU_IN, p, 2)); }
#endif

#include "/ffx/fsr1/ffx_fsr1.glsl"

bool fsr1InBounds(uvec2 p, uvec2 sizeXY) {
    return p.x < sizeXY.x && p.y < sizeXY.y;
}

#if FSR_EASU == 1
void fsr1Easu(
    vec2 renderViewportSize,
    vec2 containerTextureSize,
    vec2 upscaledViewportSize
) {
    uvec4 const0, const1, const2, const3;
    FsrEasuCon(const0, const1, const2, const3,
        float(renderViewportSize.x),
        float(renderViewportSize.y),
        float(containerTextureSize.x),
        float(containerTextureSize.y),
        float(upscaledViewportSize.x),
        float(upscaledViewportSize.y));

    uvec2 sizeXY = uvec2(imageSize(FSR1_EASU_OUT));
    uvec2 gxy = gl_GlobalInvocationID.xy;

    if (fsr1InBounds(gxy, sizeXY)) {
        AF3 gamma2Color = AF3_(0.0);
        FsrEasuF(gamma2Color, gxy, const0, const1, const2, const3);
        imageStore(FSR1_EASU_OUT, ivec2(gxy), vec4(gamma2Color, 1.0));
    }
}
#endif
