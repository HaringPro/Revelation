void RenderVanillaFog(inout vec3 scene, inout float fogTransmittance, in float viewDistance) {
    // Lava fog
	#ifdef LAVA_FOG
		if (isEyeInWater == 2) {
			fogTransmittance = saturate(viewDistance);
			scene = mix(scene, vec3(3.96, 0.68, 0.02) * EMISSIVE_BRIGHTNESS, fogTransmittance);
		}
	#endif

    // Powdered snow fog
	#ifdef POWDERED_SNOW_FOG
		if (isEyeInWater == 3) {
			fogTransmittance = exp(-viewDistance);

			vec3 scattering = global.light.skyIlluminance + global.light.directIlluminance * rPI;
			scene = mix(scattering * 0.25 * eyeSkylightSmooth, scene, fogTransmittance);
		}
	#endif

    // Blindness and darkness fog
	#ifdef BLINDNESS_DARKNESS_FOG
	    scene *= exp(-viewDistance * blindness);
	    scene *= smoothstep(12.0, 2.0, darknessFactor * viewDistance);
	#endif
}