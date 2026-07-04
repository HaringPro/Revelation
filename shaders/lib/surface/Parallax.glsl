float SampleHeight(vec2 localCoord) {
    #ifdef SMOOTH_PARALLAX
        // Bilinear interpolation
        vec2 tilePixelSize = rcp(tileScale * vec2(atlasSize));
        vec2 atlasCoord = localToAtlas(localCoord) * vec2(atlasSize);

        vec2 f = fract(atlasCoord);

        ivec2 atlasTexel00 = ivec2(atlasCoord);
	    ivec2 atlasTexel11 = ivec2(localToAtlas(localCoord + tilePixelSize) * vec2(atlasSize));

        float h00 = texelFetch(normals, atlasTexel00, 0).a;
        float h10 = texelFetch(normals, ivec2(atlasTexel11.x, atlasTexel00.y), 0).a;
        float h01 = texelFetch(normals, ivec2(atlasTexel00.x, atlasTexel11.y), 0).a;
        float h11 = texelFetch(normals, atlasTexel11, 0).a;

        return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
    #else
        return texelFetch(normals, ivec2(localToAtlas(localCoord) * vec2(atlasSize)), 0).a;
    #endif
}

vec3 HeightBasedNormal(vec2 localCoord) {
    vec2 tileSize = tileScale * vec2(atlasSize);
    vec2 tilePixelSize = rcp(tileSize);

	#ifdef SMOOTH_PARALLAX
        vec2 atlasCoord = localToAtlas(localCoord) * vec2(atlasSize);
	    vec2 f = fract(atlasCoord);

        ivec2 atlasTexel00 = ivec2(atlasCoord);
        ivec2 atlasTexel11 = ivec2(localToAtlas(localCoord + tilePixelSize) * vec2(atlasSize));

        float h00 = texelFetch(normals, atlasTexel00, 0).a;
        float h10 = texelFetch(normals, ivec2(atlasTexel11.x, atlasTexel00.y), 0).a;
        float h01 = texelFetch(normals, ivec2(atlasTexel00.x, atlasTexel11.y), 0).a;
        float h11 = texelFetch(normals, atlasTexel11, 0).a;

		vec3 normal = vec3(((h10 + h01 - h00 - h11) * f.yx + h00 - vec2(h10, h01)) * tileSize, 4.0 / PARALLAX_DEPTH);
	#else
        vec2 bias = 1e-2 * tilePixelSize;

        float heightR = SampleHeight(localCoord + vec2(bias.x, 0.0));
        float heightL = SampleHeight(localCoord - vec2(bias.x, 0.0));
        float heightU = SampleHeight(localCoord + vec2(0.0, bias.y));
        float heightD = SampleHeight(localCoord - vec2(0.0, bias.y));

        float deltaX = heightL - heightR;
        float deltaY = heightD - heightU;

		vec3 normal = vec3(deltaX, deltaY, step(abs(deltaX) + abs(deltaY), 1e-3));
	#endif

    return normalize(normal);
}

const float rSteps = 1.0 / float(PARALLAX_SAMPLES);

vec3 CalculateParallax(vec2 localCoord, vec3 tangentDir, float dither, float parallaxFade) {
	vec3 rayStep = vec3(tangentDir.xy, 1.0) * -rSteps;
	rayStep.xy *= PARALLAX_DEPTH * parallaxFade / tangentDir.z;

	vec3 rayPos = vec3(localCoord, 1.0) + rayStep * dither;

	for (uint i = 0u; i < PARALLAX_SAMPLES; ++i) {
		float sampleHeight = SampleHeight(rayPos.xy);

        if (sampleHeight > rayPos.z) break;
		rayPos += rayStep;
	}

	// Refine the parallax mapping (binary search)
	#ifdef PARALLAX_REFINEMENT
		rayPos -= rayStep;
		rayStep *= 0.5;

		for (uint i = 0u; i < PARALLAX_REFINEMENT_STEPS; ++i) {
			float sampleHeight = SampleHeight(rayPos.xy);

			rayPos += rayStep * signI(rayPos.z - sampleHeight);
			rayStep *= 0.5;
		}

		rayPos += rayStep * 2.0;
	#endif

	return rayPos;
}
