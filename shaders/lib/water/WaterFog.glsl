#if !defined INCLUDE_LIB_WATER_WATER_FOG
#define INCLUDE_LIB_WATER_WATER_FOG

float WaterPhase(float LdotV) {
	float phase = FournierForandPhase(LdotV, 1.175, 4.065);
	return mix(uniformPhase, phase, 0.8);
}

vec3 WaterSunTransmittance() {
	return exp2(-rLOG2 * waterExtinction * rcp(max(shadowDirWorld.y, 0.05)));
}

mat2x3 AnalyticWaterFog(float skylight, float waterDepth, float LdotV) {
	vec3 transmittance = exp2(-rLOG2 * waterExtinction * waterDepth);
	vec3 singleScatter = waterAlbedo * oms(transmittance);

	vec3 sunScatter = WaterPhase(LdotV) * WaterSunTransmittance() * global.directIlluminance;
	vec3 skyScatter = uniformPhase * global.skyUpIlluminance;
	vec3 scattering = singleScatter * (sunScatter + skyScatter);
	scattering *= oms(wetnessCustom * 0.8) * skylight;

	return mat2x3(scattering, transmittance);
}

//================================================================================================//

#if defined PASS_VOLUMETRIC_FOG
	vec3 CalculateWaterCaustics(ivec2 shadowTexel, float waterDepth, vec3 flatProjectOffset) {
		vec3 waveNormal = normalize(texelFetch(shadowcolor1, shadowTexel, 0).xyz * 2.0 - 1.0);
		vec3 refractDir = refract(-shadowDirWorld, waveNormal, 1.0 / WATER_IOR);

		vec3 projectOffset = refractDir * abs(1.0 / refractDir.y);
		return saturate(1.0 - 32.0 * distance(flatProjectOffset, projectOffset)) * exp2(-rLOG2 * waterExtinction * waterDepth);
	}

	mat2x3 RaymarchWaterFog(vec3 worldPos, float dither) {
		float rayLength = sdot(worldPos);
		float norm = inversesqrt(rayLength);
		rayLength = min(rayLength * norm, lodRenderDist);

		vec3 worldDir = worldPos * norm;
		vec3 flatRefractDir = refract(-shadowDirWorld, vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
		vec3 flatProjectOffset = flatRefractDir * abs(1.0 / flatRefractDir.y);

		vec3 transmittance = exp2(-rLOG2 * waterExtinction * rayLength);
		vec3 opacity = oms(transmittance);

		float sampleExtinction = minOf(waterExtinction);
		float sampleOpacity = oms(exp2(-rLOG2 * sampleExtinction * rayLength));
		vec3 extinctionRatio = waterExtinction * rcp(sampleExtinction);
		vec3 weightScale = extinctionRatio * sampleOpacity / maxEps(opacity);
		float distanceScale = rcp(rLOG2 * sampleExtinction);

		vec3 shadowDir = mat3(shadowModelView) * worldDir;
			shadowDir = diagonal3(shadowProjection) * shadowDir;

		vec3 shadowStart = transMAD(shadowModelView, gbufferModelViewInverse[3].xyz);
			shadowStart = projMAD(shadowProjection, shadowStart);

		float phase = WaterPhase(dot(shadowDirWorld, worldDir));
		vec3 sunScatter = phase * global.directIlluminance;
		vec3 skyScatter = uniformPhase * global.skyUpIlluminance * eyeSkylightSmooth;

		vec3 sumVisibility = vec3(0.0);
		vec3 sumWeight = vec3(0.0);
		const float rSteps = 1.0 / float(UW_VF_MAX_SAMPLES);
		for (uint i = 0u; i < UW_VF_MAX_SAMPLES; ++i) {
			float s = (float(i) + dither) * rSteps;
			float sampleSurvival = maxEps(oms(sampleOpacity * s));
			float logSurvival = log2(sampleSurvival);
			float t = -logSurvival * distanceScale;
			vec3 weight = weightScale * exp2(logSurvival * extinctionRatio) / sampleSurvival;

			vec3 shadowPos = shadowStart + shadowDir * t;
			vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;
			vec3 directVisibility = vec3(1.0);
			if (saturate(shadowScreenPos) == shadowScreenPos) {
				float sampleShadow = texture(shadowtex1, shadowScreenPos);
				directVisibility = vec3(sampleShadow);

				ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
				float waterMask = texelFetch(shadowcolor1, shadowTexel, 0).w;
				if (waterMask > EPS) {
					float sampleDepth0 = texelFetch(shadowtex0, shadowTexel, 0).x;
					float waterDepth = max0((sampleDepth0 - shadowScreenPos.z) * shadowProjectionInverse[2].z * 10.0);
					directVisibility *= CalculateWaterCaustics(shadowTexel, waterDepth, flatProjectOffset);
				}
			}

			sumVisibility += weight * directVisibility;
			sumWeight += weight;
		}

		vec3 directVisibility = sumVisibility / maxEps(sumWeight);
		vec3 scattering = opacity * waterAlbedo * (directVisibility * sunScatter + skyScatter);
		scattering *= oms(wetnessCustom * 0.8);
		return mat2x3(scattering, transmittance);
	}
#endif

#endif // INCLUDE_LIB_WATER_WATER_FOG
