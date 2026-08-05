//================================================================================================//

mat2x3 AnalyticWaterFog(in float skylight, in float waterDepth, in float LdotV) {
	vec3 sunTransmittance = exp2(-rLOG2 * waterExtinction * mix(4.0, 1.0, worldLightDir.y));

	#if 0
		float phase = FournierForandPhase(LdotV, 1.175, 4.065);
	#else
		float phase = DualLobePhase(LdotV, 0.95, -0.6, 0.1);
	#endif

	const vec3 msV = waterAlbedo * 0.99;
	vec3 scattering = phase + uniformPhase * msV / oms(msV);
	scattering *= oms(wetnessCustom * 0.8) * global.directIlluminance * sunTransmittance;

	vec3 transmittance = exp2(-rLOG2 * waterExtinction * waterDepth);
	scattering *= oms(transmittance) * skylight;

	return mat2x3(scattering * waterAlbedo, transmittance);
}

//================================================================================================//
// 体积雾（体积焦散）分支已禁用，仅保留分析水体雾
//#if defined PASS_VOLUMETRIC_FOG
//	... (RaymarchWaterFog 已移除)
//#endif