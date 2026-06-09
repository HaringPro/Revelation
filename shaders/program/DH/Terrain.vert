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

flat out vec3 geoNormal;
out vec3 worldPos;

out vec3 vertColor;
out vec2 lightmap;
flat out uint materialID;

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform mat4 dhProjection;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;

	lightmap = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy + gl_TextureMatrix[1][3].xy;
	lightmap = saturate((lightmap - 0.03125) * 1.06667);

	materialID = dhMaterialId == DH_BLOCK_LEAVES ? 13u : 1u;

	geoNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
