#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out float vertColor;
out vec2 texCoord;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
    vertColor = vaColor.a;
 	texCoord = vaUV0;

	vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(modelViewMatrix, vaPosition));

    float windAngle = (dot(worldPos + cameraPosition, vec3(2.0)) + frameTimeCounter * 0.2) * PI;

    worldPos.xz += worldPos.y * (0.2 + 0.1 * vec2(cos(windAngle), sin(windAngle)));
	gl_Position = diagonal4(projectionMatrix) * transMAD(gbufferModelView, worldPos).xyzz + projectionMatrix[3];

    #ifdef TAA_ENABLED
        gl_Position.xy += taaOffset * gl_Position.w;
    #endif
}