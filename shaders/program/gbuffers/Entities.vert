
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

#if defined NORMAL_MAPPING
	out mat3 tbnMatrix; // Not use flat because of the Physics mod snow
#else
	out vec3 flatNormal;
#endif

out vec4 vertColor;
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

attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform int entityId;

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	#if 0
	// Kill the nametag
	if (clamp(vaColor.a, 0.24, 0.254) == vaColor.a) {
		gl_Position = vec4(-1.0);
		return;
	}
	#endif

	vertColor = vaColor;
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	vec3 viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	// worldPos = transMAD(gbufferModelViewInverse, viewPos);
	gl_Position = diagonal4(projectionMatrix) * viewPos.xyzz + projectionMatrix[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif

	#if defined NORMAL_MAPPING
		tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
		tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * fastSign(at_tangent.w);
	#else
		flatNormal = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
	#endif

	// 829925: Physics mod snow
	materialID = entityId == 829925 ? 39u : uint(entityId - 10000);
}