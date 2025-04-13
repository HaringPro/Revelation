
uniform float blindness;
uniform float darknessFactor;

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
			const vec3 fogExtinctionCoeff = vec3(0.35, 0.65, 0.75);
			vec3 transmittance = fastExp(-fogExtinctionCoeff * viewDistance * 2.0);
			fogTransmittance = dot(transmittance, vec3(0.4));

			vec3 directIlluminance = loadDirectIllum();
			vec3 skyIlluminance = loadSkyIllum();

			vec3 scattering = skyIlluminance + directIlluminance * 0.2 * oms(wetnessCustom * 0.8);
			scattering *= rPI;

			scene = mix(scattering * eyeSkylightSmooth, scene, transmittance);
		}
	#endif

    // Blindness and darkness fog
	#ifdef BLINDNESS_DARKNESS_FOG
	    scene *= fastExp(-viewDistance * blindness);
	    scene *= remap(15.0, 3.0, darknessFactor * viewDistance);
	#endif
}
