//================================================================================================//

mat2x3 AnalyticWaterFog(float skylight, float waterDepth, float LdotV) {
	vec3 sunTransmittance = exp2(-rLOG2 * waterExtinction * mix(4.0, 1.0, worldLightDir.y));

	#if 0
		float phase = FournierForandPhase(LdotV, 1.175, 4.065);
	#else
		float phase = DualLobePhase(LdotV, 0.8, -0.6, 0.1);
	#endif

	const vec3 fms = waterAlbedo * 0.8;
	vec3 scattering = phase + uniformPhase * fms / oms(fms);
	scattering *= oms(wetnessCustom * 0.8) * global.directIlluminance * sunTransmittance;
	// scattering += uniformPhase * global.skyUpIlluminance;

	vec3 transmittance = exp2(-rLOG2 * waterExtinction * waterDepth);
	scattering *= oms(transmittance) * skylight;

	return mat2x3(scattering * waterAlbedo, transmittance);
}

//================================================================================================//

#if defined PASS_VOLUMETRIC_FOG
	#include "/lib/water/WaterWave.glsl"
	vec3 CalculateWaterCaustics(ivec2 shadowTexel, float waterDepth) {
		vec3 waveNormal = OctDecodeUnorm(texelFetch(shadowcolor1, shadowTexel, 0).xy);
		vec3 refractDir = refract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_IOR);

		vec3 projectPos = vec3(0.0, 1.0, 0.0) - refractDir * rcp(refractDir.y);
		return saturate(1.0 - 32.0 * sdot(projectPos)) * exp2(-rLOG2 * waterExtinction * waterDepth);
	}

	mat2x3 RaymarchWaterFog(vec3 worldPos, float dither) {
		float rayLength = sdot(worldPos);
		float norm = inversesqrt(rayLength);
		rayLength = min(rayLength * norm, lodRenderDist);

		vec3 worldDir = worldPos * norm;

		const float rSteps = 1.0 / float(UW_VF_MAX_SAMPLES);

		float stepLength = min(rayLength, 32.0) * rSteps;

		vec3 shadowStep = mat3(shadowModelView) * worldDir * stepLength;
			shadowStep = diagonal3(shadowProjection) * shadowStep;

		vec3 shadowStart = transMAD(shadowModelView, gbufferModelViewInverse[3].xyz);
			shadowStart = projMAD(shadowProjection, shadowStart);
		vec3 shadowPos = shadowStart + shadowStep * dither;

		// vec3 lightVector = refract(worldLightDir, vec3(0.0, -1.0, 0.0), 1.0 / WATER_IOR);

		vec4 visibility = vec4(0.0);
		for (uint i = 0u; i < UW_VF_MAX_SAMPLES; ++i, shadowPos += shadowStep) {
			vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;
			if (saturate(shadowScreenPos) != shadowScreenPos) continue;

			ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
			float sampleShadow = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x);

            vec3 absorption = vec3(1.0);
			float waterMask = texelFetch(shadowcolor1, shadowTexel, 0).w;
			if (waterMask > EPS) {
			    float sampleDepth0 = texelFetch(shadowtex0, shadowTexel, 0).x;
				float waterDepth = (sampleDepth0 - shadowScreenPos.z) * shadowProjectionInverse[2].z * 5.0;
				absorption = CalculateWaterCaustics(shadowTexel, waterDepth);
			}

			visibility += vec4(absorption, sampleShadow);
		}
		visibility *= rSteps;

		float LdotV = dot(worldLightDir, worldDir);
		#if 0
			float phase = FournierForandPhase(LdotV, 1.175, 4.065);
		#else
			float phase = DualLobePhase(LdotV, 0.8, -0.6, 0.1);
		#endif

		const vec3 fms = waterAlbedo * 0.8;
		vec3 scattering = phase * visibility.w + uniformPhase * fms / oms(fms);
		scattering *= oms(wetnessCustom * 0.8) * global.directIlluminance * visibility.xyz;
		// scattering += uniformPhase * global.skyUpIlluminance;

		vec3 transmittance = exp2(-rLOG2 * waterExtinction * rayLength);
		scattering *= oms(transmittance);

		return mat2x3(scattering * waterAlbedo, transmittance);
	}
#endif
