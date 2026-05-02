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

out vec2 texCoord;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	texCoord = gl_MultiTexCoord0.xy * vec2(RAIN_SCALE_X, RAIN_SCALE_Y);

	vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(gl_ModelViewMatrix, gl_Vertex.xyz));

	float windAngle = dot(worldPos + cameraPosition, vec3(1.0)) + frameTimeCounter * 0.05;

	worldPos.xz -= worldPos.y * 0.15 * (1.0 + vec2(cos(windAngle), sin(windAngle)));
	gl_Position = diagonal4(gl_ProjectionMatrix) * transMAD(gbufferModelView, worldPos).xyzz + gl_ProjectionMatrix[3];
}
