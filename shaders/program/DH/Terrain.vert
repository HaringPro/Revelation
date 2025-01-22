
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out vec3 flatNormal;
out vec3 worldPos;

out vec3 vertColor;
out vec2 lightmap;
flat out uint materialID;

//======// Attribute //===========================================================================//

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform mat4 dhProjection;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;

	lightmap = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy + gl_TextureMatrix[1][3].xy;
	lightmap = saturate((lightmap - 0.03125) * 1.06667);

	// materialID = uint(max0(mc_Entity.x - 1e4));
	materialID = dhMaterialId == DH_BLOCK_LEAVES ? 13u : 1u;

	flatNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

	gl_Position = diagonal4(dhProjection) * viewPos.xyzz + dhProjection[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}