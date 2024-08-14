
uniform float blindness;
uniform float darknessFactor;

void RenderVanillaFog(inout vec3 color, inout float fogTransmittance, in float viewDistance) {

    // Lava fog
	#ifdef LAVA_FOG
		if (isEyeInWater == 2) {
			fogTransmittance = saturate(viewDistance);
			color = mix(color, vec3(3.96, 0.68, 0.02) * EMISSIVE_BRIGHTNESS, fogTransmittance);
		}
	#endif

    // Powdered snow fog
	#ifdef POWDERED_SNOW_FOG
		if (isEyeInWater == 3) {
			const vec3 fogExtinctionCoeff = vec3(0.8, 0.7, 0.4);
			vec3 transmittance = fastExp(-fogExtinctionCoeff * viewDistance * 3.0);
			fogTransmittance = dot(transmittance, vec3(0.4));

			vec3 scattering = skyIlluminance * 2.0 + directIlluminance;
			scattering *= 3.0 * oneMinus(wetnessCustom * 0.7);

			color = mix(scattering * eyeSkylightFix, color, transmittance);
		}
	#endif

    // Blindness and darkness fog
	#ifdef BLINDNESS_DARKNESS_FOG
	    if (blindness > 1e-6) color *= fastExp(-viewDistance * blindness);
	    if (darknessFactor > 1e-6) color *= remap(15.0, 3.0, darknessFactor * viewDistance);
	#endif
}
