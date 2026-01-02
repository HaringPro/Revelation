
//======// Fix for https://github.com/HaringPro/Revelation/issues/18 //===========================//

in ivec2 vaUV2;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec3 worldPos;

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform vec3 chunkOffset;

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	texCoord = vaUV0;
	lightmap = saturate(vec2(vaUV2) * r240);

	#if GBUFFER_BEACONBEAM
		lightmap.x = 1.0;
	#endif

	vertColor = vaColor;

	vec3 viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	gl_Position = diagonal4(projectionMatrix) * viewPos.xyzz + projectionMatrix[3];
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}