float getRenderScaleFactor() {
    #ifdef SUPER_RESOLUTION
        return SR_RENDER_SCALE_FACTOR;
    #else
        return RENDER_SCALE;
    #endif
}

void scalePositionVertex(inout vec4 pos, vec2 jitter, float renderScaleFactor) {
    pos.xy /= pos.w;
    pos.xy = pos.xy * renderScaleFactor + renderScaleFactor - 1.0;
    #ifdef SHOULD_APPLY_JITTER
        pos.xy += jitter;
    #endif
    pos.xy *= pos.w;
}

void transformVertexPosition(out vec4 vertPos, mat4 projection, vec3 viewPos, vec2 jitter) {
    vertPos = project(projection, viewPos);
    scalePositionVertex(vertPos, jitter, getRenderScaleFactor());
}

void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
    transformVertexPosition(vertPos, gl_ProjectionMatrix, viewPos, jitter);
}

ivec2 scaleTexelPos(ivec2 texelPos, float renderScaleFactor) {
    return ivec2(vec2(texelPos) * renderScaleFactor);
}

ivec2 scaleTexelPos(ivec2 texelPos) {
    return scaleTexelPos(texelPos, getRenderScaleFactor());
}

ivec2 unscaleTexelPos(ivec2 texelPos, float renderScaleFactor) {
    return ivec2(vec2(texelPos) * rcp(renderScaleFactor));
}

ivec2 unscaleTexelPos(ivec2 texelPos) {
    return unscaleTexelPos(texelPos, getRenderScaleFactor());
}
