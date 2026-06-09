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

#define WAVING_FOLIAGE
#define WAVING_FOLIAGE_SPEED 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
#define WAVING_FOLIAGE_STRENGTH 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3 0.33 0.36 0.4 0.43 0.46 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define UNLABELLED_FOILAGE_DETECTION

//======// Output //==============================================================================//

flat out uint normalPack;
#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
flat out uint tangentPack;
#endif

out vec3 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	flat out vec2 tileScale;
	flat out vec2 tileOffset;
#endif

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(gl_ModelViewMatrix, gl_Vertex.xyz));

	materialID = uint(max(mc_Entity.x - 1e4, 1));

	// Unlabelled foilage detection
	#ifdef UNLABELLED_FOILAGE_DETECTION
		if (materialID < 1u && maxOf(abs(gl_Normal)) < 0.99) materialID = 1003u;
	#endif

	// Encode normal and tangent
	vec3 normal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	normalPack = packSnorm2x16(OctEncodeSnorm(normal));
	#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
		vec3 tangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
		tangentPack = bitfieldInsert(PackSnorm3x10(tangent), uint(at_tangent.w < 0.0), 30, 1);
	#endif

	#ifdef WAVING_FOLIAGE
		// Plants
		if (clamp(materialID, 1000u, 1002u) == materialID) {
			worldPos += cameraPosition;

			float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
			float intensity = cube(lightmap.y) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;
			float topVertex = step(gl_MultiTexCoord0.y, mc_midTexCoord.y) + float(materialID == 1001u);
			intensity *= step(materialID, 1000u) * 0.25 + 0.75; // Decrease intensity for tall plants

			float noise = textureBicubic(noisetex, (worldPos.xz + time) * 0.005).x * 2.0;

			float windOffset = sin(dot(worldPos.xz, vec2(2.0, 2.5)) + sin(time * 0.5) * 2.0);
			windOffset *= sin(dot(worldPos.xz + time * 2.0, vec2(1.0, 0.75))) + noise;
			worldPos.xz += vec2(0.4, 0.3) * windOffset * intensity * topVertex;

			worldPos -= cameraPosition;
		}

		// Leaves
		if (materialID == 13u) {
			worldPos += cameraPosition;

			float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
			float intensity = cube(lightmap.y) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;

			float noise = Pseudo3DNoise((worldPos + time) * 2.0) * 2.0;

			float windOffset = sin(dot(worldPos, vec3(2.0, 1.5, 1.5)) + sin(time * 0.5) * 2.0);
			windOffset *= sin(dot(worldPos + time * 2.0, vec3(1.0, 0.5, 0.75))) + noise;
			worldPos += vec3(0.15, 0.1, 0.1) * windOffset * intensity;

			worldPos -= cameraPosition;
		}
	#endif

	#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
        vec2 halfSize = abs(texCoord - mc_midTexCoord);
		tileScale = halfSize * 2.0;
		tileOffset = mc_midTexCoord - halfSize;
	#endif

	vec3 viewPos = transMAD(gbufferModelView, worldPos);
    transformVertexPosition(gl_Position, viewPos, taaJitter);
}
