float IORFromF0(in float f0) {
	float sqrtF0 = f0 * inversesqrt(f0);
	return (1.0 + sqrtF0) / (1.00001 - sqrtF0);
}
vec3 IORFromF0(in vec3 f0) {
	vec3 sqrtF0 = f0 * inversesqrt(f0);
	return (1.0 + sqrtF0) / (1.00001 - sqrtF0);
}

float F0FromIOR(in float ior) {
	float ratio = (ior - 1.0) / (ior + 1.0);
	return ratio * ratio;
}
vec3 F0FromIOR(in vec3 ior) {
	vec3 ratio = (ior - 1.0) / (ior + 1.0);
	return ratio * ratio;
}

struct Material {
	float roughness;
	float metalness;
	float f0;
	float emissiveness;
	bool hasReflections;
	bool isRough;
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		bool isHardcodedMetal;
		mat2x3 hardcodedMetalCoeff;
	#endif
};

// https://shaderlabs.org/wiki/LabPBR_Material_Standard
#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
	const mat2x3 GetMetalCoeff[8] = mat2x3[8]( // mat3(N, K)
		mat2x3(vec3(2.91140, 2.94970, 2.58450), vec3(3.0893, 2.9318, 2.7670)), // 230: 铁 - Iron
		mat2x3(vec3(0.18299, 0.42108, 1.37340), vec3(3.4242, 2.3459, 1.7704)), // 231: 金 - Gold
		mat2x3(vec3(1.34560, 0.96521, 0.61722), vec3(7.4746, 6.3995, 5.3031)), // 232: 铝 - Aluminium
		mat2x3(vec3(3.10710, 3.18120, 2.32300), vec3(3.3314, 3.3291, 3.1350)), // 233: 铬 - Chrome
		mat2x3(vec3(0.27105, 0.67693, 1.31640), vec3(3.6092, 2.6248, 2.2921)), // 234: 铜 - Copper
		mat2x3(vec3(1.91000, 1.83000, 1.44000), vec3(3.5100, 3.4000, 3.1800)), // 235: 铅 - Lead
		mat2x3(vec3(2.37570, 2.08470, 1.84530), vec3(4.2655, 3.7153, 3.1365)), // 236: 铂 - Platinum
		mat2x3(vec3(0.15943, 0.14512, 0.13547), vec3(3.9291, 3.1900, 2.3808))  // 237: 银 - Silver
	);

	Material GetMaterialData(in vec4 specTex) {
		Material material;

		material.roughness = sqr(1.0 - specTex.r);
		material.isHardcodedMetal = false;

		#if TEXTURE_FORMAT == 0
			uint metalIndex = uint(specTex.g * 255.0);

			if (metalIndex <= 229u) {
				// Dielectrics
				material.metalness = 0.0;
				material.f0 = mix(0.02, 1.0, specTex.g);
			} else if (metalIndex <= 237u) {
				// Hardcoded metals
				material.metalness = 1.0;
				material.isHardcodedMetal = true;
				material.hardcodedMetalCoeff = GetMetalCoeff[clamp(metalIndex - 230u, 0u, 7u)];
			} else {
				// Metals
				material.metalness = 1.0;
				material.f0 = 0.91;
			}
			#if defined PROGRAM_DEFERRED_10
				material.emissiveness = specTex.a * step(specTex.a, 0.999);
			#endif
		#else
			material.metalness = specTex.g;
			material.f0 = mix(0.02, 1.0, specTex.g);
			#if defined PROGRAM_DEFERRED_10
				material.emissiveness = specTex.b;
			#endif
		#endif

		#if defined PROGRAM_DEFERRED_10
			material.emissiveness = pow(material.emissiveness, EMISSIVE_CURVE) * EMISSIVE_BRIGHTNESS;
		#endif

		material.hasReflections = max0(0.4 - material.roughness) > 1e-2;
		material.isRough = material.roughness > ROUGH_REFLECTIONS_THRESHOLD;

		return material;
	}
#endif