
const vec3 waterAbsorption = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B);
const vec3 waterExtinction = 1e-2 + waterAbsorption;

mat2x3 CalculateWaterFog(in float skylight, in float waterDepth, in float LdotV) {
	float fogDensity = WATER_FOG_DENSITY * max(waterDepth, 1.0);

	vec3 transmittance = fastExp(-waterExtinction * fogDensity);

	float phase = HenyeyGreensteinPhase(LdotV, 0.7) + 0.1 * rPI;
	const vec3 sunTransmittance = fastExp(-waterExtinction * 5.0);
	vec3 scattering = 0.3 * oneMinus(wetnessCustom * 0.8) * directIlluminance * phase * sunTransmittance;
	scattering += 0.01 * mix(skyIlluminance * 0.4, vec3(GetLuminance(skyIlluminance) * 0.1), 0.7 * wetnessCustom);
	scattering *= oneMinus(transmittance) * skylight / waterExtinction;

	return mat2x3(scattering, transmittance);
}

#if defined PROGRAM_COMPOSITE
	mat2x3 UnderwaterVolumetricFog(in vec3 worldPos, in vec3 worldDir, in float dither) {
		float rayLength = min(far, length(worldPos));

		uint steps = uint(UW_VOLUMETRIC_FOG_SAMPLES * 0.5 + 0.4 * rayLength);
			 steps = min(steps, UW_VOLUMETRIC_FOG_SAMPLES);

		float rSteps = 1.0 / float(steps);

		float stepLength = rayLength * rSteps * UW_VOLUMETRIC_FOG_DENSITY;

		vec3 shadowStart = WorldPosToShadowPos(gbufferModelViewInverse[3].xyz),
			 shadowEnd = WorldPosToShadowPos(worldDir * stepLength + gbufferModelViewInverse[3].xyz);

		vec3 shadowStep = shadowEnd - shadowStart,
			 shadowPosition = shadowStep * dither + shadowStart;

		vec3 stepTransmittance = fastExp(-waterExtinction * stepLength);
		vec3 transmittance = vec3(1.0);

		vec3 scatteringSun = vec3(0.0);
		vec3 scatteringSky = vec3(0.0);

		uint i = 0u;
		while (++i < steps) {
			shadowPosition += shadowStep;

			vec3 shadowScreenPos = DistortShadowSpace(shadowPosition) * 0.5 + 0.5;
			if (saturate(shadowScreenPos) != shadowScreenPos) continue;

			ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
		
			float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, shadowTexel, 0).x);
			vec3 sampleSunlight = vec3(1.0);

			if (sampleDepth0 < 1.0) {
				sampleSunlight = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).xxx);

				if (sampleSunlight.x != sampleDepth0) {
					float waterDepth = abs(texelFetch(shadowcolor1, shadowTexel, 0).w * 512.0 - 128.0 - shadowPosition.y - eyeAltitude);
					if (waterDepth > 0.1) {
						sampleSunlight = pow5(texelFetch(shadowcolor0, shadowTexel, 0).rgb);
					} else {
						vec3 shadowColorSample = cube(texelFetch(shadowcolor0, shadowTexel, 0).rgb);
						sampleSunlight = shadowColorSample * (sampleSunlight - sampleDepth0) + vec3(sampleDepth0);
					}

					sampleSunlight *= fastExp(-waterExtinction * 0.6 * UW_VOLUMETRIC_FOG_DENSITY * max(waterDepth, 6.0));
				}
			}

			scatteringSun += sampleSunlight * transmittance;
			scatteringSky += transmittance;

			transmittance *= stepTransmittance;
		}

		float LdotV = dot(worldLightVector, worldDir);
		float phase = HenyeyGreensteinPhase(LdotV, 0.7) + 0.1;

		vec3 scattering = scatteringSun * 0.3 * oneMinus(wetnessCustom * 0.8) * phase * directIlluminance;
		scattering += scatteringSky * 0.01 * mix(skyIlluminance * 0.4, vec3(GetLuminance(skyIlluminance) * 0.1), 0.7 * wetnessCustom);
		scattering *= oneMinus(stepTransmittance) / waterExtinction;

		return mat2x3(scattering, transmittance);
	}
#endif