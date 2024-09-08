
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define SELECTION_BOX_WIDTH 2.5 // Width of the outline in pixels. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 150.0 200.0 250.0 300.0 350.0 400.0 450.0 500.0]

#define SELECTION_BOX_COLOR_R 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define SELECTION_BOX_COLOR_G 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define SELECTION_BOX_COLOR_B 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

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
	lightmap = saturate(vec2(vaUV2) * r240);

    if (renderStage == MC_RENDER_STAGE_OUTLINE) {
        const mat4 viewScale = mat4(255.0 / 256.0);

        vec4 linePosStart = projectionMatrix * modelViewMatrix * vec4(vaPosition, 1.0) * viewScale;
        vec4 linePosEnd = projectionMatrix * modelViewMatrix * vec4(vaPosition + vaNormal, 1.0) * viewScale;
        vec3 NDCStart = linePosStart.xyz / linePosStart.w;
        vec3 NDCEnd = linePosEnd.xyz / linePosEnd.w;
        vec2 lineScreenDir = normalize((NDCEnd.xy - NDCStart.xy) * viewSize);
        vec2 lineOffset = vec2(-lineScreenDir.y, lineScreenDir.x) * SELECTION_BOX_WIDTH * viewPixelSize;
        if (lineScreenDir.y < 0.0) lineOffset *= -1.0;
        gl_Position = vec4(linePosStart.w);
        if (gl_VertexID % 2 == 0) gl_Position.xyz *= NDCStart + vec3(lineOffset, 0.0);
        else gl_Position.xyz *= NDCStart - vec3(lineOffset, 0.0);

        tint.rgb = vec3(SELECTION_BOX_COLOR_R, SELECTION_BOX_COLOR_G, SELECTION_BOX_COLOR_B);
        lightmap = vec2(dot(tint.rgb, vec3(0.333333)));
    } else {
        vec3 viewPos = transMAD(modelViewMatrix, vaPosition);
        gl_Position = diagonal4(projectionMatrix) * viewPos.xyzz + projectionMatrix[3];
    }

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}