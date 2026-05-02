void RenderVanillaFog(inout vec3 color, inout float fogTransmittance, float viewDistance) {
	// Lava fog
	#ifdef LAVA_FOG
		if (isEyeInWater == 2) {
			fogTransmittance = exp2(-4.0 * viewDistance);
			color = mix(vec3(3.96, 0.68, 0.02) * EMISSIVE_BRIGHTNESS, color, fogTransmittance);
		}
	#endif

	// Powdered snow fog
	#ifdef POWDERED_SNOW_FOG
		if (isEyeInWater == 3) {
			fogTransmittance = exp(-viewDistance);

			vec3 scattering = global.skyUpIlluminance + global.directIlluminance * rPI;
			color = mix(scattering * 0.25 * eyeSkylightSmooth, color, fogTransmittance);
		}
	#endif

	// Blindness and darkness fog
	#ifdef BLINDNESS_DARKNESS_FOG
		color *= exp(-viewDistance * blindness);
		color *= smoothstep(12.0, 2.0, darknessFactor * viewDistance);
	#endif
}
