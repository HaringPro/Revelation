
struct Material {
	float roughness;
	float metalness;
	float f0;
	float emissiveness;
	bool hasReflections;
	bool isRough;
	#if defined MC_SPECULAR_MAP
		bool isHardcodedMetal;
		mat2x3 hardcodedMetalCoeff;
	#endif
};

#define EMISSIVE_CURVE 2.2 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

// https://shaderlabs.org/wiki/LabPBR_Material_Standard
#if defined MC_SPECULAR_MAP
	const mat2x3 GetMetalCoeff[8] = mat2x3[8](
							//--// N //--//				 //--// K //--//
		mat2x3(vec3(2.91140, 2.94970, 2.58450), vec3(3.0893, 2.9318, 2.7670)), // 230: 铁 - Iron
		mat2x3(vec3(0.18299, 0.42108, 1.37340), vec3(3.4242, 2.3459, 1.7704)), // 231: 金 - Gold
		mat2x3(vec3(1.34560, 0.96521, 0.61722), vec3(7.4746, 6.3995, 5.3031)), // 232: 铝 - Aluminium
		mat2x3(vec3(3.10710, 3.18120, 2.32300), vec3(3.3314, 3.3291, 3.1350)), // 233: 铬 - Chrome
		mat2x3(vec3(0.27105, 0.67693, 1.31640), vec3(3.6092, 2.6248, 2.2921)), // 234: 铜 - Copper
		mat2x3(vec3(1.91000, 1.83000, 1.44000), vec3(3.5100, 3.4000, 3.1800)), // 235: 铅 - Lead
		mat2x3(vec3(2.37570, 2.08470, 1.84530), vec3(4.2655, 3.7153, 3.1365)), // 236: 铂 - Platinum
		mat2x3(vec3(0.15943, 0.14512, 0.13547), vec3(3.9291, 3.1900, 2.3808))  // 237: 银 - Silver
	);
#endif

Material GetMaterialData(in vec4 specTex) {
	Material material;

	material.roughness = sqr(1.0 - specTex.r);
	#if defined MC_SPECULAR_MAP
		#if TEXTURE_FORMAT == 0
			if (specTex.g > (229.5 / 255.0)) {
				material.metalness = 1.0;
				material.f0 = 0.91;
			} else {
				material.metalness = 0.0;
				material.f0 = specTex.g;			
			}
			material.emissiveness = specTex.a == 1.0 ? 0.0 : specTex.a;
		#else
			material.metalness = specTex.g;
			material.f0 = specTex.g * 0.96 + 0.04;
			material.emissiveness = specTex.b;
		#endif

		material.emissiveness = pow(material.emissiveness, EMISSIVE_CURVE);
	#else
		material.metalness = 0.0;
		material.f0 = specTex.g;
		material.emissiveness = 0.0;
	#endif

	material.hasReflections = specTex.r + material.metalness > 5e-3;
	material.isRough = material.roughness > ROUGH_REFLECTIONS_THRESHOLD;

	return material;
}

Material GetMaterialData(in vec2 specTex) {
	Material material;

	material.roughness = specTex.r;
	#if defined MC_SPECULAR_MAP
		material.isHardcodedMetal = false;

		#if TEXTURE_FORMAT == 0
			if (specTex.g < (229.5 / 255.0)) {
				material.metalness = 0.0;
				material.f0 = specTex.g;			
			} else if (specTex.g < 237.5 / 255.0) {
				material.metalness = 1.0;
				material.isHardcodedMetal = true;
				material.hardcodedMetalCoeff = GetMetalCoeff[clamp(uint(specTex.g * 255.0) - 230u, 0u, 7u)];
			} else {
				material.metalness = 1.0;
				material.f0 = 0.91;
			}
		#else
			material.metalness = specTex.g;
			material.f0 = specTex.g * 0.96 + 0.04;
		#endif
	#else
		material.metalness = 0.0;
		material.f0 = specTex.g;
	#endif

	material.hasReflections = max0(0.625 - material.roughness) + material.metalness > 5e-3;
	material.isRough = material.roughness > ROUGH_REFLECTIONS_THRESHOLD;

	return material;
}
