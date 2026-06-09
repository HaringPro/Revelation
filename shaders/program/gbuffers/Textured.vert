/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#define RENDER_SCALE_VERTEX
#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec3 worldPos;

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);
	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	#if GBUFFER_BEACONBEAM
		lightmap.x = 1.0;
	#endif

	vertColor = gl_Color;

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
