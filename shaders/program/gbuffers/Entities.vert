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

#if defined MC_NORMAL_MAP
	out mat3 tbnMatrix;
#else
	out vec3 geoNormal;
#endif

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

//======// Attribute //===========================================================================//

in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform int entityId;

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
	#if 0
	// Kill the nametag
	if (clamp(gl_Color.a, 0.24, 0.254) == gl_Color.a) {
		gl_Position = vec4(-1.0);
		return;
	}
	#endif

	vertColor = gl_Color;
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	// worldPos = transMAD(gbufferModelViewInverse, viewPos);
	gl_Position = project(gl_ProjectionMatrix, viewPos);

    #ifdef SUPER_RESOLUTION
        transformVertexPosition(
            gl_Position,
            taaJitter,
            SR_RENDER_SCALE_FACTOR
        );
     #else
        transformVertexPosition(
            gl_Position,
            taaJitter,
            MC_RENDER_SCALE_FACTOR
        );
     #endif

	#if defined MC_NORMAL_MAP
		tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
		tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
		tbnMatrix[1] = signMul(cross(tbnMatrix[0], tbnMatrix[2]), at_tangent.w);
	#else
		geoNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	#endif

	// 829925: Physics mod snow
	materialID = entityId == 829925 ? 39u : uint(entityId - 10000);
}
