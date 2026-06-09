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

//======// Output //==============================================================================//

out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0) * vec2(RAIN_SCALE_X, RAIN_SCALE_Y);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
    vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

    float windAngle = dot(worldPos + cameraPosition, vec3(1.0)) + frameTimeCounter * 0.05;
    worldPos.xz -= worldPos.y * 0.15 * (1.0 + vec2(cos(windAngle), sin(windAngle)));

    viewPos = transMAD(gbufferModelView, worldPos);
    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
