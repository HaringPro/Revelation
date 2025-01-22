
const vec3 waterAbsorption = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B);
const vec3 waterExtinction = 1e-2 + waterAbsorption;

//================================================================================================//

FogData CalculateWaterFog(in float skylight, in float waterDepth, in float LdotV) {
	float fogDensity = WATER_FOG_DENSITY * max(waterDepth, 1.0);

	vec3 transmittance = fastExp(-waterExtinction * fogDensity);

	float phase = HenyeyGreensteinPhase(LdotV, 0.7) * 0.7 + isotropicPhase * 0.3;
	const vec3 sunTransmittance = fastExp(-waterExtinction * 5.0);

	vec3 scattering = rPI * oneMinus(wetnessCustom * 0.8) * directIlluminance * 2e-2 * phase * sunTransmittance;
	scattering += 1e-2 * mix(skyIlluminance * 0.4, vec3(GetLuminance(skyIlluminance) * 0.1), 0.7 * wetnessCustom);
	scattering *= oneMinus(transmittance) * skylight / waterExtinction;

	return FogData(scattering, transmittance);
}

//================================================================================================//

#if defined PASS_COMPOSITE
	vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
		float NdotD = dot(normal, dir);
		float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
		if (k < 0.0) return vec3(0.0);

		return dir * eta - normal * (sqrt(k) + NdotD * eta);
	}

	#include "/lib/water/WaterWave.glsl"
	float CalculateWaterCaustics(in vec3 rayPos, in vec3 lightVector) {
		vec2 waveCoord = rayPos.xz - rayPos.y * (1.0 + lightVector.xz / lightVector.y);
		vec3 waveNormal = CalculateWaterNormal(waveCoord).xzy;
		vec3 refractVector = fastRefract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_REFRACT_IOR);

		vec3 refractPos = vec3(0.0, 1.0, 0.0) - refractVector / refractVector.y;

		return saturate(dotSelf(refractPos) * 32.0);
	}

	FogData UnderwaterVolumetricFog(in vec3 worldPos, in float dither) {
		float rayLength = dotSelf(worldPos);
		float norm = inversesqrt(rayLength);
		rayLength = min(rayLength * norm, far);

		vec3 worldDir = worldPos * norm;

		uint steps = uint(UW_VOLUMETRIC_FOG_SAMPLES * 0.5 + 0.4 * rayLength);
			 steps = min(steps, UW_VOLUMETRIC_FOG_SAMPLES);

		float rSteps = 1.0 / float(steps);

		float stepLength = rayLength * rSteps * UW_VOLUMETRIC_FOG_DENSITY;

		vec3 rayStart = gbufferModelViewInverse[3].xyz + cameraPosition,
			 rayStep  = worldDir * stepLength;
		vec3 rayPos = rayStart + rayStep * dither;

		vec3 shadowStep = mat3(shadowModelView) * worldDir * stepLength;
			 shadowStep = diagonal3(shadowProjection) * shadowStep;
		vec3 shadowPos = WorldPosToShadowPos(gbufferModelViewInverse[3].xyz) + shadowStep * dither;

		vec3 stepTransmittance = fastExp(-waterExtinction * stepLength);
		vec3 lightVector = fastRefract(worldLightVector, vec3(0.0, -1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
		vec3 transmittance = vec3(1.0);

		vec3 scatteringSun = vec3(0.0);
		vec3 scatteringSky = vec3(0.0);

		uint i = 0u;
		while (++i < steps) {
			rayPos += rayStep;
			shadowPos += shadowStep;

			vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;
			if (saturate(shadowScreenPos) != shadowScreenPos) continue;

			ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
		
			float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, shadowTexel, 0).x);
			vec3 sampleSunlight = vec3(1.0);

			if (sampleDepth0 < 1.0) {
				sampleSunlight = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).xxx);

				if (sampleSunlight.x != sampleDepth0) {
					float waterDepth = abs(texelFetch(shadowcolor1, shadowTexel, 0).w * 512.0 - 128.0 - shadowPos.y - eyeAltitude);
					if (waterDepth > 0.1) {
						sampleSunlight = vec3(CalculateWaterCaustics(rayPos, lightVector));
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

		float LdotV = dot(lightVector, worldDir);
		float phase = HenyeyGreensteinPhase(LdotV, 0.7) * 0.7 + isotropicPhase * 0.3;

		vec3 scattering = scatteringSun * 2e-2 * oneMinus(wetnessCustom * 0.8) * phase * directIlluminance;
		scattering += scatteringSky * 1e-2 * mix(skyIlluminance * 0.4, vec3(GetLuminance(skyIlluminance) * 0.1), 0.7 * wetnessCustom);
		scattering *= oneMinus(stepTransmittance) / waterExtinction;

		return FogData(scattering, transmittance);
	}
#endif