
const vec3 waterAbsorption = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B);
const vec3 waterScattering = vec3(0.015);
const vec3 waterExtinction = waterAbsorption + waterScattering;

//================================================================================================//

mat2x3 CalculateWaterFog(in float skylight, in float waterDepth, in float LdotV) {
	float fogDensity = WATER_FOG_DENSITY * max(waterDepth, 1.0);

	vec3 transmittance = exp2(-rLOG2 * waterExtinction * fogDensity);

	float phase = HenyeyGreensteinPhase(LdotV, 0.85) * 0.75 + uniformPhase * 0.25;
	const vec3 sunTransmittance = exp2(-rLOG2 * waterExtinction * 8.0);

	vec3 directIlluminance = loadDirectIllum();
	vec3 skyIlluminance = loadSkyIllum();

	vec3 scattering = oms(wetnessCustom * 0.8) * phase * directIlluminance * sunTransmittance;
	scattering += uniformPhase * skyIlluminance;
	scattering *= oms(transmittance) * skylight;

	return mat2x3(scattering * (waterScattering / waterExtinction), transmittance);
}

//================================================================================================//

#if defined PASS_VOLUMETRIC_FOG
	vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
		float NdotD = dot(normal, dir);
		float k = 1.0 - eta * eta * oms(NdotD * NdotD);
		if (k < 0.0) return vec3(0.0);

		return dir * eta - normal * (sqrt(k) + NdotD * eta);
	}

	#include "/lib/water/WaterWave.glsl"
	float CalculateWaterCaustics(in vec3 rayPos, in vec3 lightVector) {
		vec2 waveCoord = rayPos.xz - rayPos.y / lightVector.y * lightVector.xz;
		vec3 waveNormal = CalculateWaterNormal(waveCoord).xzy;
		vec3 refractDir = fastRefract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_REFRACT_IOR);

		vec3 projectPos = vec3(0.0, 1.0, 0.0) - refractDir / refractDir.y;
		return exp2(-256.0 * sdot(projectPos));
	}

	mat2x3 UnderwaterVolumetricFog(in vec3 worldPos, in float dither) {
		float rayLength = sdot(worldPos);
		float norm = inversesqrt(rayLength);
		rayLength = min(rayLength * norm, far);

		vec3 worldDir = worldPos * norm;

		uint steps = uint(float(UW_VOLUMETRIC_FOG_SAMPLES) * saturate(0.5 + 0.5 * rayLength));

		float rSteps = 1.0 / float(steps);

		float stepLength = min(rayLength, 48.0) * rSteps * UW_VOLUMETRIC_FOG_DENSITY;

		vec3 rayStart = gbufferModelViewInverse[3].xyz,
			 rayStep  = worldDir * stepLength;
		vec3 rayPos = rayStart + rayStep * dither + cameraPosition;

		vec3 shadowStep = mat3(shadowModelView) * worldDir * stepLength;
			 shadowStep = diagonal3(shadowProjection) * shadowStep;

		vec3 shadowStart = transMAD(shadowModelView, rayStart);
			 shadowStart = projMAD(shadowProjection, shadowStart);
		vec3 shadowPos = shadowStart + shadowStep * dither;

		vec3 stepTransmittance = exp2(-rLOG2 * waterExtinction * stepLength);
		vec3 lightVector = fastRefract(worldLightVector, vec3(0.0, -1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
		vec3 transmittance = vec3(1.0);

		vec3 scatteringSun = vec3(0.0);

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
				#ifdef COLORED_VOLUMETRIC_FOG
					} else {
						vec3 shadowColorSample = cube(texelFetch(shadowcolor0, shadowTexel, 0).rgb);
						sampleSunlight = shadowColorSample * (sampleSunlight - sampleDepth0) + vec3(sampleDepth0);
				#endif
					}

					sampleSunlight *= exp2(-rLOG2 * waterExtinction * UW_VOLUMETRIC_FOG_DENSITY * max(waterDepth, 8.0));
				}
			}

			scatteringSun += sampleSunlight * transmittance;
			transmittance *= stepTransmittance;
		}

		float LdotV = dot(lightVector, worldDir);
		float phase = HenyeyGreensteinPhase(LdotV, 0.85) * 0.75 + uniformPhase * 0.25;

		vec3 directIlluminance = loadDirectIllum();
		vec3 skyIlluminance = loadSkyIllum();

		scatteringSun *= oms(wetnessCustom * 0.8) * phase * directIlluminance;
		vec3 scatteringSky = uniformPhase * skyIlluminance;

		transmittance = exp2(-rLOG2 * waterExtinction * UW_VOLUMETRIC_FOG_DENSITY * rayLength);
		vec3 scattering = scatteringSun * oms(stepTransmittance) + scatteringSky * oms(transmittance);

		return mat2x3(scattering * (waterScattering / waterExtinction), transmittance);
	}
#endif