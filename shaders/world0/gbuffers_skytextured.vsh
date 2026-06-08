#version 460 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec3 vertColor;
out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = diagonal4(gl_ProjectionMatrix) * viewPos.xyzz + gl_ProjectionMatrix[3];
    #ifdef SUPER_RESOLUTION
        transformVertexPosition(
            gl_Position,
            taaJitter,
            SR_RENDER_SCALE_FACTOR
        );
     #else
        transformVertexPosition(
            gl_Position,
            taaJitter,
            MC_RENDER_SCALE_FACTOR
        );
     #endif
}
