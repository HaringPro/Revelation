
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec3 flatNormal;

out vec4 tint;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;
in ivec2 vaUV2;
in vec3 vaNormal;

//======// Uniform //=============================================================================//

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	tint = vaColor;
	flatNormal = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);

	materialID = lightmap.x > 0.99 ? 20u : 40u;

	vec3 viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	gl_Position = diagonal4(projectionMatrix) * viewPos.xyzz + projectionMatrix[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}