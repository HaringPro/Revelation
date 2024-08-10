
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec4 tint;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 viewPos;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;
in ivec2 vaUV2;
in vec3 vaNormal;

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform int blockEntityId;

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	tint = vaColor;
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	gl_Position = projectionMatrix * vec4(viewPos, 1.0);

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
	// vec4 worldPos = gbufferModelViewInverse * viewPos;

	materialID = uint(blockEntityId - 10000);
}