
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

flat out mat3 tbnMatrix;

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

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 mc_Entity;
attribute vec4 at_tangent;

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

    tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
	#if defined MC_NORMAL_MAP
		tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * sign(at_tangent.w);
	#endif

	materialID = uint(max0(mc_Entity.x - 1e4));

	gl_Position = projectionMatrix * modelViewMatrix * vec4(vaPosition + chunkOffset, 1.0);

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}