#define atlasCoord(coord) (tileOffset + tileScale * fract(coord))
#define atlasTexel(coord) ivec2((tileOffset + tileScale * fract(coord)) * vec2(atlasSize))

const float rSteps = 1.0 / float(PARALLAX_SAMPLES);

vec3 CalculateParallax(vec3 tangentDir, float dither, float parallaxFade) {
	vec3 rayStep = vec3(tangentDir.xy, 1.0) * -rSteps;
	rayStep.xy *= PARALLAX_DEPTH * parallaxFade / tangentDir.z;

	vec3 rayPos = vec3(tileBase, 1.0) + rayStep * dither;

	float sampleHeight;
	for (uint i = 0u; i < PARALLAX_SAMPLES && sampleHeight < rayPos.z; ++i) {
		rayPos += rayStep;
		sampleHeight = texelFetch(normals, atlasTexel(rayPos.xy), 0).a;
	}

	// Refine the parallax mapping (binary search)
	#ifdef PARALLAX_REFINEMENT
		rayPos -= rayStep;
		rayStep *= 0.5;

		for (uint i = 0u; i < PARALLAX_REFINEMENT_STEPS; ++i) {
			sampleHeight = texelFetch(normals, atlasTexel(rayPos.xy), 0).a;

			rayPos += rayStep * (step(sampleHeight, rayPos.z) * 2.0 - 1.0);
			rayStep *= 0.5;
		}

		rayPos += rayStep * 2.0;
	#endif

	return rayPos;
}

float CalculateParallaxShadow(vec3 tangentDir, vec3 rayPos, float dither, float parallaxFade) {
	vec3 rayStep = vec3(tangentDir.xy, 1.0) * rayPos.z * rSteps;
	rayStep.xy *= PARALLAX_DEPTH * parallaxFade / tangentDir.z;
	rayPos += rayStep * dither;

	for (uint i = 0u; i < PARALLAX_SAMPLES; ++i) {
		float sampleHeight = texelFetch(normals, atlasTexel(rayPos.xy), 0).a;

		if (sampleHeight > rayPos.z) return 1.0;
		rayPos += rayStep;
	}

	return 0.0;
}
