#if !defined INCLUDE_UNIVERSAL_MATERIAL
#define INCLUDE_UNIVERSAL_MATERIAL

float IORFromF0(float f0) {
	float sqrtF0 = f0 * inversesqrt(f0);
	return (1.0 + sqrtF0) / (1.00001 - sqrtF0);
}
vec3 IORFromF0(vec3 f0) {
	vec3 sqrtF0 = f0 * inversesqrt(f0);
	return (1.0 + sqrtF0) / (1.00001 - sqrtF0);
}

float F0FromIOR(float ior) {
	float ratio = (ior - 1.0) / (ior + 1.0);
	return ratio * ratio;
}
vec3 F0FromIOR(vec3 ior) {
	vec3 ratio = (ior - 1.0) / (ior + 1.0);
	return ratio * ratio;
}

struct Material {
	float roughness;
	float metallic;
	float emission;
    vec3 reflectance;
	bool specularMask;
	bool mirrorMask;
};

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

vec3 GetMaterialF0(float metallic, vec3 albedo) {
	#if TEXTURE_FORMAT == 0
		vec3 f0;
		uint metalIndex = uint(metallic * 255.0);

		if (metalIndex < 230u) {
			// Dielectrics
			f0 = vec3(mix(DEFAULT_DIELECTRIC_F0, 1.0, metallic));
	#ifdef LABPBR_HARDCODED_METAL
		} else if (metalIndex < 238u) {
			// Hardcoded metals
			f0 = HardcodedMetalF0[metalIndex - 230u];
	#endif
		} else {
			// Other metals
			f0 = albedo;
		}
		return f0;
	#else
		return mix(vec3(DEFAULT_DIELECTRIC_F0), albedo, metallic);
	#endif
}

Material GetMaterialData(vec4 specTex, vec3 albedo) {
	Material material;

	material.roughness = sqr(1.0 - specTex.r);
	material.metallic = specTex.g;

	#if TEXTURE_FORMAT == 0
		material.emission = specTex.a * step(specTex.a, 0.999);
	#else
		material.emission = specTex.b;
	#endif
	material.emission = pow(material.emission, EMISSIVE_CURVE) * EMISSIVE_BRIGHTNESS;

    material.reflectance = GetMaterialF0(material.metallic, albedo);

	material.specularMask = material.roughness < 0.5 || material.metallic > EPS;
	material.mirrorMask = material.roughness < ROUGH_REFLECTIONS_THRESHOLD;

	return material;
}

Material GetMaterialData(vec2 specTex) {
	Material material;

	material.roughness = sqr(1.0 - specTex.r);
	material.metallic = specTex.g;

	material.specularMask = material.roughness < 0.5 || material.metallic > EPS;
	material.mirrorMask = material.roughness < ROUGH_REFLECTIONS_THRESHOLD;

	return material;
}

#endif
