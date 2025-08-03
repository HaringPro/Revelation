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
	float emissiveness;
	bool specularMask;
	bool isRough;
};

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
	// https://shaderlabs.org/wiki/LabPBR_Material_Standard
	const mat2x3 HardcodedMetalCoeff[8] = mat2x3[8]( // mat3(N, K)
		mat2x3(vec3(2.91140, 2.94970, 2.58450), vec3(3.0893, 2.9318, 2.7670)), // 铁 - Iron
		mat2x3(vec3(0.18299, 0.42108, 1.37340), vec3(3.4242, 2.3459, 1.7704)), // 金 - Gold
		mat2x3(vec3(1.34560, 0.96521, 0.61722), vec3(7.4746, 6.3995, 5.3031)), // 铝 - Aluminium
		mat2x3(vec3(3.10710, 3.18120, 2.32300), vec3(3.3314, 3.3291, 3.1350)), // 铬 - Chromium
		mat2x3(vec3(0.27105, 0.67693, 1.31640), vec3(3.6092, 2.6248, 2.2921)), // 铜 - Copper
		mat2x3(vec3(1.91000, 1.83000, 1.44000), vec3(3.5100, 3.4000, 3.1800)), // 铅 - Lead
		mat2x3(vec3(2.37570, 2.08470, 1.84530), vec3(4.2655, 3.7153, 3.1365)), // 铂 - Platinum
		mat2x3(vec3(0.15943, 0.14512, 0.13547), vec3(3.9291, 3.1900, 2.3808))  // 银 - Silver
	);

	// https://physicallybased.info
	const vec3 HardcodedMetalF0[8] = vec3[8](
		vec3(0.612, 0.541, 0.422), // 铁 - Iron
		vec3(1.000, 0.973, 0.597), // 金 - Gold
		vec3(0.981, 0.979, 0.961), // 铝 - Aluminium
		vec3(0.675, 0.720, 0.711), // 铬 - Chromium
		vec3(0.999, 0.946, 0.705), // 铜 - Copper
		vec3(0.819, 0.804, 0.769), // 铅 - Lead
		vec3(0.816, 0.786, 0.671), // 铂 - Platinum
		vec3(0.999, 0.998, 0.986)  // 银 - Silver
	);

	Material GetMaterialData(in vec4 specTex) {
		Material material;

		material.roughness = sqr(1.0 - specTex.r);
		material.metalness = specTex.g;

		#if TEXTURE_FORMAT == 0
			material.emissiveness = specTex.a * step(specTex.a, 0.999);
		#else
			material.emissiveness = specTex.b;
		#endif
		material.emissiveness = pow(material.emissiveness, EMISSIVE_CURVE) * EMISSIVE_BRIGHTNESS;

		material.specularMask = saturate(0.4 - material.roughness) + material.metalness > 1e-2;
		material.isRough = material.roughness + wetnessCustom > ROUGH_REFLECTIONS_THRESHOLD;

		return material;
	}

	Material GetMaterialData(in vec2 specTex) {
		Material material;

		material.roughness = sqr(1.0 - specTex.r);
		material.metalness = specTex.g;

		material.specularMask = saturate(0.4 - material.roughness) + material.metalness > 1e-2;
		material.isRough = material.roughness + wetnessCustom > ROUGH_REFLECTIONS_THRESHOLD;

		return material;
	}
#endif