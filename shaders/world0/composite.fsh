#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute volumetric fog

--------------------------------------------------------------------------------
*/

#define PASS_COMPOSITE

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 11,12 */
layout (location = 0) out vec3 scatteringOut;
layout (location = 1) out vec3 transmittanceOut;

//======// Input //===============================================================================//

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in mat2x3 fogExtinctionCoeff;
flat in mat2x3 fogScatteringCoeff;

//======// Uniform //=============================================================================//

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform vec3 fogWind;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"

#include "/lib/atmospherics/Global.glsl"
#ifdef VF_CLOUD_SHADOWS
	#include "/lib/atmospherics/clouds/Shadows.glsl"
#endif

const vec2 falloffScale = 1.0 / vec2(12.0, 36.0);

const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

//================================================================================================//

#include "/lib/lighting/ShadowDistortion.glsl"

vec3 WorldPosToShadowPos(in vec3 worldPos) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	return shadowClipPos;
}

#if VOLUMETRIC_FOG_QUALITY == 0
	/* Low */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		return exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - vec2(2.0));
	}
#elif VOLUMETRIC_FOG_QUALITY == 1
	/* Medium */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		vec2 density = exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - 2.0);

		rayPos *= 0.07;
		rayPos += fogWind;
		float noise = Calculate3DNoise(rayPos) * 3.0;
		noise -= Calculate3DNoise(rayPos * 4.0 + fogWind);

		density.x *= saturate(noise * 8.0 - 6.0) * 1.4;

		return density;
	}
#endif

FogData AirVolumetricFog(in vec3 worldPos, in float dither) {
	#if defined DISTANT_HORIZONS
		#define far float(dhRenderDistance)
		const uint steps = VOLUMETRIC_FOG_SAMPLES << 1u;
	#else
		const uint steps = VOLUMETRIC_FOG_SAMPLES;
	#endif

	const float rSteps = 1.0 / float(steps);

	const float toExp6 = 2.58497;

	float rayLength = dotSelf(worldPos);
	float norm = inversesqrt(rayLength);
	rayLength = min(rayLength * norm, far);

	vec3 worldDir = worldPos * norm;

	vec3 rayStart = gbufferModelViewInverse[3].xyz + cameraPosition,
		 rayStep  = worldDir * rayLength;

	vec3 shadowStart = WorldPosToShadowPos(gbufferModelViewInverse[3].xyz),
		 shadowStep  = mat3(shadowModelView) * rayStep;
	     shadowStep = diagonal3(shadowProjection) * shadowStep;

	rayLength *= toExp6 * 0.2 * rSteps;

	vec3 scatteringSun = vec3(0.0);
	vec3 scatteringSky = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	float LdotV = dot(worldLightVector, worldDir);
	vec2 phase = vec2(HenyeyGreensteinPhase(LdotV, 0.6) * 0.6 + HenyeyGreensteinPhase(LdotV, -0.3) * 0.3 + HenyeyGreensteinPhase(LdotV, 0.9) * 0.1, RayleighPhase(LdotV));
	phase.x = mix(isotropicPhase, phase.x, 0.6);
	float baseDensity = 6.0 / far;

	for (uint i = 0u; i < steps; ++i) {
		float stepExp = exp2(toExp6 * (float(i) + dither) * rSteps);
		float stepLength = (stepExp - 1.0) * 0.2; // Normalize to [0, 1]

		vec3 rayPos = rayStart + stepLength * rayStep;
		vec3 shadowPos = shadowStart + stepLength * shadowStep;

		#if MC_VERSION < 11800
			if (rayPos.y > 256.0) continue;
		#else
			if (rayPos.y > 384.0) continue;
		#endif

		vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;

		vec2 stepFogmass = CalculateFogDensity(rayPos) + baseDensity;
		stepFogmass *= stepExp * rayLength;

		if (dot(stepFogmass, vec2(1.0)) < 1e-6) continue; // Faster than maxOf()

		#ifdef COLORED_VOLUMETRIC_FOG
			vec3 sampleShadow = vec3(1.0);
			if (saturate(shadowScreenPos) == shadowScreenPos) {
				ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
				sampleShadow = step(shadowScreenPos.z, vec3(texelFetch(shadowtex1, shadowTexel, 0).x));

				float sampleDepth0 = step(shadowScreenPos.z, texelFetch(shadowtex0, shadowTexel, 0).x);
				if (sampleShadow.x != sampleDepth0) {
					vec3 shadowColorSample = pow4(texelFetch(shadowcolor0, shadowTexel, 0).rgb);
					sampleShadow = shadowColorSample * (sampleShadow - sampleDepth0) + vec3(sampleDepth0);
				}
			}
		#else
			float sampleShadow = 1.0;
			if (saturate(shadowScreenPos) == shadowScreenPos) {
				ivec2 shadowTexel = ivec2(shadowScreenPos.xy * realShadowMapRes);
				sampleShadow = step(shadowScreenPos.z, texelFetch(shadowtex1, shadowTexel, 0).x);
			}
		#endif

		#ifdef VF_CLOUD_SHADOWS
			// float cloudShadow = CalculateCloudShadows(rayPos);
			float cloudShadow = ReadCloudShadowMap(colortex10, rayPos - cameraPosition);
			sampleShadow *= cloudShadow * cloudShadow;
		#endif

		vec3 opticalDepth = fogExtinctionCoeff * stepFogmass;
		vec3 stepTransmittance = exp2(-opticalDepth);

		vec3 stepScattering = transmittance * oneMinus(stepTransmittance) / maxEps(opticalDepth);
		// stepScattering *= 2.0 * oneMinus(fastExp(-opticalDepth * 4.0)); // Powder Effect

		scatteringSun += fogScatteringCoeff * (stepFogmass * phase) * sampleShadow * stepScattering;
		scatteringSky += fogScatteringCoeff * stepFogmass * stepScattering;

		transmittance *= stepTransmittance;

		if (dot(transmittance, vec3(1.0)) < 1e-3) break; // Faster than maxOf()
	}

	vec3 scattering = scatteringSun * rPI * directIlluminance;
	scattering += scatteringSky * mix(skyIlluminance, directIlluminance * 1e-2, wetness * 0.4 + 0.2);
	scattering *= eyeSkylightSmooth;

	return FogData(scattering, transmittance);
}

#include "/lib/water/WaterFog.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy * 2.0);

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize * 2.0;
	vec3 screenPos = vec3(screenCoord, loadDepth0(screenTexel));

	vec3 viewPos = ScreenToViewSpace(screenPos);
	#if defined DISTANT_HORIZONS
		if (screenPos.z > 0.999999) {
			screenPos.z = loadDepth0DH(screenTexel);
			viewPos = ScreenToViewSpaceDH(screenPos);
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;

	float dither = BlueNoiseTemporal(screenTexel);

	FogData volFogData = FogData(vec3(0.0), vec3(1.0));

	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			volFogData = AirVolumetricFog(worldPos, dither);
		}
	#endif
	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			volFogData = UnderwaterVolumetricFog(worldPos, dither);
		}
	#endif

	scatteringOut = volFogData.scattering;
	transmittanceOut = volFogData.transmittance;

	// Apply bayer dithering to reduce banding artifacts
	transmittanceOut += (dither - 0.5) * r255;
}