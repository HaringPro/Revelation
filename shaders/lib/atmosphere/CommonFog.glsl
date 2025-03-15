
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
			const vec3 fogExtinctionCoeff = vec3(0.8, 0.7, 0.4);
			vec3 transmittance = fastExp(-fogExtinctionCoeff * viewDistance * 3.0);
			fogTransmittance = dot(transmittance, vec3(0.4));

			vec3 directIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 0), 0).rgb;
			vec3 skyIlluminance = texelFetch(colortex5, ivec2(skyViewRes.x, 1), 0).rgb;

			vec3 scattering = skyIlluminance * 2.0 + directIlluminance * 0.03;
			scattering *= 3.0 * oms(wetnessCustom * 0.7);

			scene = mix(scattering * eyeSkylightSmooth, scene, transmittance);
		}
	#endif

    // Blindness and darkness fog
	#ifdef BLINDNESS_DARKNESS_FOG
	    scene *= fastExp(-viewDistance * blindness);
	    scene *= remap(15.0, 3.0, darknessFactor * viewDistance);
	#endif
}
