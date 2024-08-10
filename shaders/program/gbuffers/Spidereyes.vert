//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec4 tint;
out vec2 texCoord;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	tint = vaColor;
	texCoord = vaUV0;

	vec4 viewPos = modelViewMatrix * vec4(vaPosition + chunkOffset, 1.0);
	gl_Position = projectionMatrix * viewPos;

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}