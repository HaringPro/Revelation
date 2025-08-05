
//======// Fix for https://github.com/HaringPro/Revelation/issues/18 //===========================//

in ivec2 vaUV2;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 viewPos;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;
in vec3 vaNormal;

in vec4 at_tangent;

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
	vertColor = vaColor;
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	gl_Position = diagonal4(projectionMatrix) * viewPos.xyzz + projectionMatrix[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
	// vec4 worldPos = gbufferModelViewInverse * viewPos;

	materialID = uint(blockEntityId - 10000);
}