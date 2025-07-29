
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

flat out vec3 flatNormal;

out vec4 vertColor;
out vec2 lightmap;
flat out uint materialID;

out vec3 worldPos;
out vec3 viewPos;

//======// Attribute //===========================================================================//

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 mc_Entity;
attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform sampler2D colortex4; // Global illuminances

uniform mat4 dhProjection;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

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
	lightmap = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy + gl_TextureMatrix[1][3].xy;
	lightmap = saturate((lightmap - 0.03125) * 1.06667);

	vertColor = gl_Color;

	flatNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

	materialID = dhMaterialId == DH_BLOCK_WATER ? 3u : 2u;

	#ifdef PHYSICS_OCEAN
		// basic texture to determine how shallow/far away from the shore the water is
		physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r;
		// transform gl_Vertex (since it is the raw mesh, i.e. not transformed yet)
		vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), gl_Vertex.z, gl_Vertex.w);
		// pass this to the fragment shader to fetch the texture there for per fragment normals
		physics_localPosition = finalPosition.xyz;
		viewPos = transMAD(gl_ModelViewMatrix, finalPosition.xyz);
	#else
		viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	#endif
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

	gl_Position = diagonal4(dhProjection) * viewPos.xyzz + dhProjection[3];
	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}