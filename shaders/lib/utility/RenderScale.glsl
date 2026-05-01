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
