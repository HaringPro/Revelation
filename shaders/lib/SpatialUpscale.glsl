#if defined PASS_DEFERRED_LIGHTING
#if defined SSILVB_ENABLED && defined SVGF_ENABLED
	vec3 SpatialUpscale(in ivec2 texel, in vec3 worldNormal, in float viewDistance, in float NdotV) {
		vec3 sum = texelFetch(colortex3, texel, 0).rgb;
		float sumWeight = 1.0;

		float sigmaZ = -4.0 * NdotV;

		ivec2 tileOffset = ivec2(halfViewSize.x, 0);
        ivec2 texelEnd = ivec2(halfViewEnd) - 1;

		float depthTolerance = saturate(0.05 + viewDistance * 0.02);

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = clamp(texel + offset3x3N[i], ivec2(1), texelEnd);

			vec3 prevData = texelFetch(colortex2, sampleTexel + tileOffset, 0).rgb;

			float weight = pow16(saturate(dot(OctDecodeSnorm(prevData.xy), worldNormal)));
			weight *= exp2(max0(distance(prevData.z, viewDistance) - depthTolerance) * sigmaZ);

			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

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
	mat2x3 UnpackFogData(in uvec3 data) {
		vec2 unpackedZ = unpackHalf2x16(data.z);
		vec3 scattering = vec3(unpackHalf2x16(data.x), unpackedZ.x);
		vec3 transmittance = vec3(unpackUnorm2x16(data.y), unpackedZ.y);
		return mat2x3(scattering, transmittance);
	}

	mat2x3 VolumetricFogSpatialUpscale(in ivec2 texelPos, in float linearDepth) {
		ivec2 randTexel = ivec2(vec2(texelPos >> 1) + BlueNoise(texelPos, frameCounter));
		float sigmaZ = -64.0 / linearDepth;

		mat2x3 sum = UnpackFogData(texelFetch(colortex11, randTexel, 0).rgb);
		float sumWeight = 1.0;

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = randTexel + offset3x3N[i];
			uvec4 sampleFogData = texelFetch(colortex11, sampleTexel, 0);

			float sampleDepth = uintBitsToFloat(sampleFogData.w);
			float weight = exp2(abs(sampleDepth - linearDepth) * sigmaZ);

			sum += UnpackFogData(sampleFogData.rgb) * weight;
			sumWeight += weight;
		}

		sum *= rcp(sumWeight);
		return sum;
	}
#endif
#endif