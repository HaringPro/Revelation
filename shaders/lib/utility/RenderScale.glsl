#if RENDER_SCALE_1000X != 1000
    void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
	    vertPos = project(gl_ProjectionMatrix, viewPos);
        vertPos.xy /= vertPos.w;
        vertPos.xy = vertPos.xy * RENDER_SCALE + RENDER_SCALE - 1.0;
        #ifdef TAA_ENABLED
            vertPos.xy += jitter;
        #endif
        vertPos.xy *= vertPos.w;
    }

    ivec2 scaleTexelPos(ivec2 texelPos) {
        return ivec2(vec2(texelPos) * RENDER_SCALE);
    }

    ivec2 unscaleTexelPos(ivec2 texelPos) {
        return ivec2(vec2(texelPos) * rcp(RENDER_SCALE));
    }
#else
    void transformVertexPosition(out vec4 vertPos, vec3 viewPos, vec2 jitter) {
	    vertPos = project(gl_ProjectionMatrix, viewPos);
        #ifdef TAA_ENABLED
            vertPos.xy += jitter * vertPos.w;
        #endif
    }

    #define scaleTexelPos(texelPos) texelPos
    #define unscaleTexelPos(texelPos) texelPos
#endif
