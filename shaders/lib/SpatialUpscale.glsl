#if defined PASS_DEFERRED_LIGHTING
#if (defined SSPT_ENABLED && defined SVGF_ENABLED) || defined RSM_ENABLED
	vec3 SpatialUpscale5x5(in ivec2 texel, in vec3 worldNormal, in float viewDistance, in float NdotV) {
		float sumWeight = 1.0;

		vec4 sum = texelFetch(colortex3, texel, 0);
		float centerLuma = luminance(sum.rgb);

		float variancePhi = -2.0 * inversesqrt(sum.a + EPS);
		float sigmaZ = -2.0 * NdotV;

		ivec2 offsetToBR = ivec2(halfViewSize.x, 0);
        ivec2 texelEnd = ivec2(halfViewEnd);

		for (uint i = 0u; i < 24u; ++i) {
			ivec2 sampleTexel = clamp(texel + offset5x5N[i], ivec2(0), texelEnd);
			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

			vec4 prevData = texelFetch(colortex2, sampleTexel + offsetToBR, 0);

			float weight = pow32(saturate(dot(prevData.rgb, worldNormal)));
			weight *= exp2(distance(prevData.a, viewDistance) * sigmaZ + abs(centerLuma - luminance(sampleLight.rgb)) * variancePhi);

			if (weight < 1e-5) continue;

			sum.rgb += sampleLight * weight;
			sumWeight += weight;
		}

		return sum.rgb * rcp(sumWeight);
	}
#endif
#endif

//================================================================================================//

#if defined PASS_COMPOSITE
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	mat2x3 UnpackFogData(in uvec3 data) {
		vec2 unpackedZ = unpackHalf2x16(data.z);
		vec3 scattering = vec3(unpackHalf2x16(data.x), unpackedZ.x);
		vec3 transmittance = vec3(unpackUnorm2x16(data.y), unpackedZ.y);
		return mat2x3(scattering, transmittance);
	}

	mat2x3 VolumetricFogSpatialUpscale(in ivec2 texel, in float linearDepth) {
		const ivec2 offset[4] = ivec2[4](
			ivec2(-1, -1), ivec2(-1, 1), ivec2(1, -1), ivec2(1, 1)
		);

		float sigmaZ = -64.0 / linearDepth;
		mat2x3 sum = mat2x3(vec3(0.0), vec3(0.0));
		float sumWeight = 0.0;

		for (uint i = 0u; i < 4u; ++i) {
			ivec2 sampleTexel = texel + offset[i];
			uvec4 sampleFogData = texelFetch(colortex11, sampleTexel, 0);

			float sampleDepth = uintBitsToFloat(sampleFogData.w);
			float weight = maxEps(exp2(abs(sampleDepth - linearDepth) * sigmaZ));

			sum += UnpackFogData(sampleFogData.rgb) * weight;
			sumWeight += weight;
		}

		sum *= rcp(sumWeight);
		return sum;
	}
#endif
#endif