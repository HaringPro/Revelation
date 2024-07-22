#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/settings.glsl"

//======// Output //==============================================================================//

out float tint;
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
    tint = vaColor.a;
 	texCoord = vaUV0;

	vec4 worldPos = gbufferModelViewInverse * modelViewMatrix * vec4(vaPosition, 1.0);

    float windPos = dot(worldPos.xyz + cameraPosition, vec3(2.0));
    float wind = fma(sin(windPos + frameTimeCounter * 0.1), 0.25, 0.2);
	const float windAngle = 3.1415926535898 / 60.0;

    worldPos.xz += worldPos.y * wind * vec2(cos(windAngle), sin(windAngle));
    gl_Position = projectionMatrix * gbufferModelView * worldPos;

    #ifdef TAA_ENABLED
        gl_Position.xy += taaOffset * gl_Position.w;
    #endif
}