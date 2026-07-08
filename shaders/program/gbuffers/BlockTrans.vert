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

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 worldPos;

//======// Attribute //===========================================================================//

in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform int blockEntityId;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;
uniform vec2 renderScale;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	materialID = blockEntityId < 10000 ? 502u : uint(blockEntityId - 10000 + 500);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

    gl_Position = project(gl_ProjectionMatrix, viewPos);
    #ifdef SHOULD_APPLY_JITTER
        gl_Position.xy += taaJitter * gl_Position.w;
    #endif
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        gl_Position.xy = gl_Position.xy * renderScale + (renderScale - 1.0) * gl_Position.w;
    #endif
}
