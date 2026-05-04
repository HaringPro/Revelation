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

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color;
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	materialID = uint(blockEntityId - 10000);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = project(gl_ProjectionMatrix, viewPos);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

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
