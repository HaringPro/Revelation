void scalePositionVertex(
    inout vec4 pos,
    vec2 jitter,
    float renderScaleFactor
) {
    pos.xy /= pos.w;
    pos.xy = pos.xy * renderScaleFactor + renderScaleFactor - 1.0;
    pos.xy += jitter;
    pos.xy *= pos.w;
}

void transformVertexPosition(
    inout vec4 position,
    vec2 jitter,
    float renderScaleFactor
) {
    #ifdef TAA_ENABLED
    scalePositionVertex(
        position,
        jitter,
        renderScaleFactor
    );
    #else
    scalePositionVertex(
        position,
        vec2(0.0),
        renderScaleFactor
    );
    #endif
}

ivec2 scaleTexelPos(ivec2 texelPos, float renderScaleFactor) {
    return ivec2(vec2(texelPos) * renderScaleFactor);
}

ivec2 scaleTexelPos(ivec2 texelPos) {
    return scaleTexelPos(texelPos, MC_RENDER_SCALE_FACTOR);
}

vec2 scaleScreenCoord(vec2 screenCoord, float renderScaleFactor) {
    return screenCoord * renderScaleFactor;
}

vec2 scaleScreenCoord(vec2 screenCoord) {
    return scaleScreenCoord(screenCoord, MC_RENDER_SCALE_FACTOR);
}

ivec2 unscaleTexelPos(ivec2 texelPos, float renderScaleFactor) {
    return ivec2(vec2(texelPos) * (1.0 / renderScaleFactor));
}

vec2 unscaleScreenCoord(vec2 screenCoord, float renderScaleFactor) {
    return screenCoord * (1.0 / renderScaleFactor);
}

ivec2 unscaleTexelPos(ivec2 texelPos) {
    return unscaleTexelPos(texelPos, MC_RENDER_SCALE_FACTOR);
}

vec2 unscaleScreenCoord(vec2 screenCoord) {
    return unscaleScreenCoord(screenCoord, MC_RENDER_SCALE_FACTOR);
}


vec2 scaleViewSize(vec2 viewSize, float renderScaleFactor) {
    return viewSize * renderScaleFactor;
}

vec2 scaleViewSize(vec2 viewSize) {
    return scaleViewSize(viewSize, MC_RENDER_SCALE_FACTOR);
}

vec2 scaleViewPixelSize(vec2 viewPixelSize, float renderScaleFactor) {
    return viewPixelSize * (1.0 / renderScaleFactor);
}

vec2 scaleViewPixelSize(vec2 viewPixelSize) {
    return scaleViewPixelSize(viewPixelSize, MC_RENDER_SCALE_FACTOR);
}

vec2 unscaleViewSize(vec2 viewSize, float renderScaleFactor) {
    return viewSize * (1.0 / renderScaleFactor);
}

vec2 unscaleViewPixelSize(vec2 viewPixelSize, float renderScaleFactor) {
    return viewPixelSize * renderScaleFactor;
}

vec2 unscaleViewSize(vec2 viewSize) {
    return unscaleViewSize(viewSize, MC_RENDER_SCALE_FACTOR);
}

vec2 unscaleViewPixelSize(vec2 viewPixelSize) {
    return unscaleViewPixelSize(viewPixelSize, MC_RENDER_SCALE_FACTOR);
}
