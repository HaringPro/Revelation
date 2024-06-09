
mat2x3 CalculateWaterFog(in float skylight, in float waterDepth, in float LdotV) {
	float fogDensity = WATER_FOG_DENSITY * 1.6 * max(waterDepth, 1.0);

    const vec3 waterAbsorption = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B);
	vec3 waterExtinction = 1e-2 + waterAbsorption;

	vec3 transmittance = fastExp(-waterExtinction * fogDensity);

	float phase = HenyeyGreensteinPhase(LdotV, 0.65) + 0.1 * rPI;
	vec3 scattering = mix(skyIlluminance * 0.4, vec3(GetLuminance(skyIlluminance) * 0.1), 0.7 * wetnessCustom);
	scattering *= 0.01 + 0.4 * oneMinus(wetnessCustom * 0.8) * directIlluminance * phase;
	scattering *= oneMinus(transmittance) * skylight / waterExtinction;

	return mat2x3(scattering, transmittance);
}
