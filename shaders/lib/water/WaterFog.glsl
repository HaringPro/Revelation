
vec4 WaterFog(in float skylight, in float waterDepth) {
	float fogDensity = WATER_FOG_DENSITY * fma(0.1, wetnessCustom * eyeSkylightFix, 0.16) * max(1.0, waterDepth);

	vec3 waterFogColor = vec3(0.035, 0.5, 0.7) * rPI;

    const vec3 waterAbsorption = vec3(0.25, 0.04, 0.01);
	vec3 transmittance = fastExp(-(waterAbsorption * 8.0 + 0.03) * fogDensity);

	return vec4(waterFogColor * skylight * oneMinus(transmittance), GetLuminance(1.0 - transmittance));
}
