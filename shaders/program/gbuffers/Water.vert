
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out mat3 tbnMatrix;

out vec4 tint;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 worldPos;
out vec3 viewPos;

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

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

uniform sampler2D colortex5;

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
	tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
	tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * fastSign(at_tangent.w);

	materialID = uint(max(mc_Entity.x - 1e4, 2.0));

	viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

	gl_Position = projectionMatrix * vec4(viewPos, 1.0);
	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif

	directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
	skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;
}