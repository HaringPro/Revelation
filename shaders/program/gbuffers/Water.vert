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

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

out vec3 worldPos;

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

//======// Function //============================================================================//

#define PHYSICS_OCEAN_SUPPORT
#ifdef PHYSICS_OCEAN_SUPPORT
#endif

#ifdef PHYSICS_OCEAN
	#define PHYSICS_VERTEX
	#include "/lib/water/PhysicsOceans.glsl"
#endif

//======// Main //================================================================================//
void main() {
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);
	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	// Nether portal
	lightmap.x = float(mc_Entity.x == 11500.0);

	vertColor = gl_Color;

	materialID = mc_Entity.x == 10003.0 ? 3u : 2u;

	#ifdef PHYSICS_OCEAN
		// basic texture to determine how shallow/far away from the shore the water is
		physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r;
		// transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
		vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), gl_Vertex.z, gl_Vertex.w);
		// pass this to the fragment shader to fetch the texture there for per fragment normals
		physics_localPosition = finalPosition.xyz;
		vec3 viewPos = transMAD(gl_ModelViewMatrix, finalPosition.xyz);
	#else
		vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	#endif
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
