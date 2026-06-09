#ifdef RENDER_SCALE_VERTEX
    void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
	    vertPos = project(gl_ProjectionMatrix, viewPos);
        #if RENDER_SCALE_1000X != 1000
            vertPos.xy = vertPos.xy * RENDER_SCALE + (RENDER_SCALE - 1.0) * vertPos.w;
        #endif
        #ifdef TAA_ENABLED
            vertPos.xy += jitter * vertPos.w;
        #endif
    }
#endif

#if RENDER_SCALE_1000X != 1000
    #define scaleTexelPos(texelPos) ivec2(vec2(texelPos) * RENDER_SCALE)
    #define unscaleTexelPos(texelPos) ivec2(vec2(texelPos) * rcp(RENDER_SCALE))
#else
    #define scaleTexelPos(texelPos) texelPos
    #define unscaleTexelPos(texelPos) texelPos
#endif
