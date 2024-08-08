#if defined PROGRAM_DEFERRED_10
#if defined SSPT_ENABLED && defined SVGF_ENABLED
	vec3 SpatialUpscale5x5(in ivec2 texel, in vec3 worldNormal, in float viewDistance, in float NdotV) {
		float sumWeight = 0.1;

		vec3 total = texelFetch(colortex3, texel, 0).rgb;
		float centerLuma = GetLuminance(total);
		total *= sumWeight;

		ivec2 shift = ivec2(viewWidth * 0.5, 0);
        ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

		for (uint i = 0u; i < 24u; ++i) {
			ivec2 sampleTexel = texel + offset5x5N[i];
			if (clamp(sampleTexel, ivec2(0), maxLimit) == sampleTexel) {
				vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

				vec4 prevData = texelFetch(colortex13, sampleTexel + shift, 0);

				float weight = sqr(pow16(max0(dot(prevData.rgb, worldNormal))));
				weight *= exp2(-distance(prevData.a, viewDistance) * NdotV);
				weight *= exp2(-abs(centerLuma - GetLuminance(sampleLight.rgb)) * 0.4);

				if (weight < 1e-5) continue;

				total += sampleLight * weight;
				sumWeight += weight;
			}
		}

		return total / sumWeight;
	}
#endif
#endif

//================================================================================================//

#if defined PROGRAM_COMPOSITE_4
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	mat2x3 VolumetricFogSpatialUpscale(in vec2 coord, in float linearDepth) {
		ivec2 bias = ivec2(coord + frameCounter) % 2;
		ivec2 texel = ivec2(coord * 0.5) + bias * 2;

		const ivec2 offset[4] = ivec2[4](
			ivec2(-2,-2), ivec2(-2, 0),
			ivec2( 0, 0), ivec2( 0,-2)
		);

		float sigmaZ = 64.0 / linearDepth;
		mat2x3 total = mat2x3(0.0);
		float sumWeight = 0.0;

		for (uint i = 0u; i < 4u; ++i) {
			ivec2 sampleTexel = texel + offset[i];
			float sampleDepth = ScreenToLinearDepth(sampleDepth(sampleTexel * 2));
			float weight = maxEps(exp2(-abs(sampleDepth - linearDepth) * sigmaZ));
			total += mat2x3(texelFetch(colortex11, sampleTexel, 0).rgb, texelFetch(colortex12, sampleTexel, 0).rgb) * weight;
			sumWeight += weight;
		}

		return total / sumWeight;
	}
#endif
#endif