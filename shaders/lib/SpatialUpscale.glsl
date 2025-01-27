#if defined PASS_DEFERRED_LIGHTING
#if (defined SSPT_ENABLED && defined SVGF_ENABLED) || defined RSM_ENABLED
	vec3 SpatialUpscale5x5(in ivec2 texel, in vec3 worldNormal, in float viewDistance, in float NdotV) {
		float sumWeight = 0.2;

		vec3 sum = texelFetch(colortex3, texel, 0).rgb;
		float centerLuma = GetLuminance(sum);
		sum *= sumWeight;

		ivec2 offsetToBR = ivec2(halfViewSize.x, 0);
        ivec2 texelEnd = ivec2(halfViewEnd);

		for (uint i = 0u; i < 24u; ++i) {
			ivec2 sampleTexel = clamp(texel + offset5x5N[i], ivec2(0), texelEnd);
			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

			vec4 prevData = texelFetch(colortex13, sampleTexel + offsetToBR, 0);

			float weight = sqr(pow16(max0(dot(prevData.rgb, worldNormal))));
			weight *= exp2(-distance(prevData.a, viewDistance) * 2.0 * NdotV);
			weight *= exp2(-abs(centerLuma - GetLuminance(sampleLight.rgb)) * 0.4);

			if (weight < 1e-5) continue;

			sum += sampleLight * weight;
			sumWeight += weight;
		}

		return sum * rcp(sumWeight);
	}
#endif
#endif

//================================================================================================//

#if defined PASS_COMPOSITE
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	FogData VolumetricFogSpatialUpscale(in vec2 coord, in float linearDepth) {
		ivec2 bias = ivec2(coord + frameCounter) % 2;
		ivec2 texel = ivec2(coord) + bias * 2 - 2;

		const ivec2 offset[5] = ivec2[5](
			ivec2(-2, -2), ivec2(-2, 2), ivec2(0, 0), ivec2(2, -2), ivec2(2, 2)
		);

		float sigmaZ = -1e2 / linearDepth;
		FogData sum = FogData(vec3(0.0), vec3(0.0));
		float sumWeight = 0.0;

		for (uint i = 0u; i < 5u; ++i) {
			ivec2 sampleTexel = texel + offset[i];
			float sampleDepth = FetchLinearDepth(sampleTexel);
			float weight = maxEps(exp2(abs(sampleDepth - linearDepth) * sigmaZ));

			ivec2 halfTexel = sampleTexel >> 1;
			sum.scattering += texelFetch(colortex11, halfTexel, 0).rgb * weight;
			sum.transmittance += texelFetch(colortex12, halfTexel, 0).rgb * weight;
			sumWeight += weight;
		}

		float rSumWeight = rcp(sumWeight);
		sum.scattering *= rSumWeight;
		sum.transmittance *= rSumWeight;

		return sum;
	}
#endif
#endif