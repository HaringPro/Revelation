#if RENDER_SCALE_1000X != 1000 || defined(SUPER_RESOLUTION)
    #ifndef RENDER_SCALE_NO_VERTEX_TRANSFORM
    void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
	    vertPos = project(gl_ProjectionMatrix, viewPos);
        vertPos.xy /= vertPos.w;
        vertPos.xy = vertPos.xy * RENDER_SCALE + RENDER_SCALE - 1.0;
        #ifdef SHOULD_APPLY_JITTER
            vertPos.xy += jitter;
        #endif
        vertPos.xy *= vertPos.w;
    }
    #endif

    ivec2 scaleTexelPos(ivec2 texelPos) {
        return ivec2(vec2(texelPos) * RENDER_SCALE);
    }

    ivec2 unscaleTexelPos(ivec2 texelPos) {
        return ivec2(vec2(texelPos) * rcp(RENDER_SCALE));
    }
#else
    #ifndef RENDER_SCALE_NO_VERTEX_TRANSFORM
    void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
	    vertPos = project(gl_ProjectionMatrix, viewPos);
        #ifdef SHOULD_APPLY_JITTER
            vertPos.xy += jitter * vertPos.w;
        #endif
    }
    #endif

    #define scaleTexelPos(texelPos) texelPos
    #define unscaleTexelPos(texelPos) texelPos
#endif
