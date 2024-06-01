
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

flat out vec4 tint;
out vec2 lightmap;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in ivec2 vaUV2;
in vec3 vaNormal;

//======// Uniform //=============================================================================//

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec2 taaOffset;
uniform vec2 viewSize;
uniform vec2 viewPixelSize;

uniform int renderStage;

//======// Main //================================================================================//
void main() {
	tint = vaColor;
	lightmap = saturate(vec2(vaUV2) * rcp(240.0));

    if (renderStage == MC_RENDER_STAGE_OUTLINE) {
        const float lineWidth = 3.0;
        const mat4 viewScale = mat4(255.0 / 256.0);

        vec4 linePosStart = projectionMatrix * modelViewMatrix * vec4(vaPosition, 1.0) * viewScale;
        vec4 linePosEnd = projectionMatrix * modelViewMatrix * vec4(vaPosition + vaNormal, 1.0) * viewScale;
        vec3 NDCStart = linePosStart.xyz / linePosStart.w;
        vec3 NDCEnd = linePosEnd.xyz / linePosEnd.w;
        vec2 lineScreenDirection = normalize((NDCEnd.xy - NDCStart.xy) * viewSize);
        vec2 lineOffset = vec2(-lineScreenDirection.y, lineScreenDirection.x) * lineWidth * viewPixelSize;
        if (lineScreenDirection.y < 0.0) lineOffset *= -1.0;
        gl_Position = vec4(linePosStart.w);
        if (gl_VertexID % 2 == 0) gl_Position.xyz *= NDCStart + vec3(lineOffset, 0.0);
        else gl_Position.xyz *= NDCStart - vec3(lineOffset, 0.0);

        tint = vec4(1.0);
    } else {
    	gl_Position = projectionMatrix * modelViewMatrix * vec4(vaPosition, 1.0);
    }

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}