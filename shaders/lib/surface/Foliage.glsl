#if !defined INCLUDE_SURFACE_FOLIAGE
#define INCLUDE_SURFACE_FOLIAGE

#include "/lib/universal/Random.glsl"

#define WAVING_FOLIAGE
#define WAVING_FOLIAGE_SPEED 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
#define WAVING_FOLIAGE_STRENGTH 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3 0.33 0.36 0.4 0.43 0.46 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// #define INTERACTIVE_PLANT

// Apply identical geometry displacement in the terrain and shadow passes.
void ApplyFoliageDisplacement(inout vec3 worldPos, uint materialID, float skylight, float topVertexMask) {
	bool plantMask = materialID >= MATERIAL_ROOTED_BASE;
	#ifdef INTERACTIVE_PLANT
		if (plantMask && sdot(worldPos) < 4.0) {
			worldPos.xz *= 1.0 + exp2(3.0 - length(worldPos * vec3(8.0, 2.0, 8.0)));
		}
	#endif

	#ifdef WAVING_FOLIAGE
		// Plants
		if (plantMask) {
			vec3 minecraftPos = worldPos + cameraPosition;

			float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
			float intensity = cube(skylight) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;
			float topVertex = topVertexMask + float(materialID == MAT_TALL_UPPER);
			intensity *= materialID == MAT_TALL_UPPER || materialID == MAT_TALL_LOWER ? 0.75 : 1.0;

			float noise = textureBicubic(noisetex, (minecraftPos.xz + time) * 0.005).x * 2.0;

			float windOffset = sin(dot(minecraftPos.xz, vec2(2.0, 2.5)) + sin(time * 0.5) * 2.0);
			windOffset *= sin(dot(minecraftPos.xz + time * 2.0, vec2(1.0, 0.75))) + noise;
			worldPos.xz += vec2(0.4, 0.3) * windOffset * intensity * topVertex;
		}

		// Leaves
		if (materialID == MAT_LEAVES) {
			vec3 minecraftPos = worldPos + cameraPosition;

			float time = frameTimeCounter * WAVING_FOLIAGE_SPEED;
			float intensity = cube(skylight) * (wetness + 1.0) * WAVING_FOLIAGE_STRENGTH;

			float noise = Pseudo3DNoise((minecraftPos + time) * 2.0) * 2.0;

			float windOffset = sin(dot(minecraftPos, vec3(2.0, 1.5, 1.5)) + sin(time * 0.5) * 2.0);
			windOffset *= sin(dot(minecraftPos + time * 2.0, vec3(1.0, 0.5, 0.75))) + noise;
			worldPos += vec3(0.15, 0.1, 0.1) * windOffset * intensity;
		}
	#endif
}

#endif
