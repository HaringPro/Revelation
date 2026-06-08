/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out uint normalPack;
#if defined MC_NORMAL_MAP
flat out uint tangentPack;
#endif

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;

//======// Attribute //===========================================================================//

in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = project(gl_ProjectionMatrix, viewPos);

	transformVertexPosition(
		gl_Position,
		taaJitter,
		MC_RENDER_SCALE_FACTOR
	);

	// Encode normal and tangent
	vec3 normal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	normalPack = packSnorm2x16(OctEncodeSnorm(normal));
	#if defined MC_NORMAL_MAP
		vec3 tangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
        uint tangentSign = (floatBitsToUint(at_tangent.w) & 0x80000000u) | 0x3F800000u;
		tangentPack = bitfieldInsert(PackSnorm3x10(tangent), tangentSign, 30, 2);
	#endif

	#ifdef TAA_ENABLED
		gl_Position.xy += taaJitter * gl_Position.w;
	#endif
}
