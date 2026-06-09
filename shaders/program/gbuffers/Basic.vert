/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#define RENDER_SCALE_VERTEX
#include "/lib/Utility.glsl"

#define SELECTION_BOX_COLOR_R 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define SELECTION_BOX_COLOR_G 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define SELECTION_BOX_COLOR_B 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//======// Output //==============================================================================//

flat out vec4 vertColor;
out vec2 lightmap;

//======// Uniform //=============================================================================//

uniform int renderStage;
uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color;
	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	if (renderStage == MC_RENDER_STAGE_OUTLINE) {
		vertColor.rgb = vec3(SELECTION_BOX_COLOR_R, SELECTION_BOX_COLOR_G, SELECTION_BOX_COLOR_B);
		lightmap = vec2(0.0);
	}

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
