
mat2x3 CalculateWaterFog(in float skylight, in float waterDepth) {
	float fogDensity = WATER_FOG_DENSITY * 0.2 * clamp(waterDepth, 1.0, far);

    const vec3 waterAbsorption = vec3(0.25, 0.04, 0.01);
	vec3 transmittance = fastExp(-(waterAbsorption * 8.0 + 0.03) * fogDensity);

	vec3 scattering = skyIlluminance * rPI * oneMinus(transmittance) * skylight;

	return mat2x3(scattering, transmittance);
}
