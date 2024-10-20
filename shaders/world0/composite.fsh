#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute volumetric fog

--------------------------------------------------------------------------------
*/

#define PROGRAM_COMPOSITE

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
		return max(exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - vec2(2.0)), 0.07);
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

		return max(density, 0.07);
	}
#endif

mat2x3 AirVolumetricFog(in vec3 worldPos, in float dither) {
	float rayLength = dotSelf(worldPos);
	float norm = inversesqrt(dotSelf(worldPos));
	rayLength = min(rayLength * norm, far);

	vec3 worldDir = worldPos * norm;

	uint steps = uint(VOLUMETRIC_FOG_SAMPLES * 0.4 + rayLength * 0.1);
		 steps = min(steps, VOLUMETRIC_FOG_SAMPLES);

	float rSteps = 1.0 / float(steps);

	float stepLength = rayLength * rSteps;

	vec3 rayStep = worldDir * stepLength,
		 rayPos  = rayStep * dither + gbufferModelViewInverse[3].xyz + cameraPosition;

	vec3 shadowStart = WorldPosToShadowPos(gbufferModelViewInverse[3].xyz),
		 shadowEnd 	 = WorldPosToShadowPos(rayStep + gbufferModelViewInverse[3].xyz);

	vec3 shadowStep = shadowEnd - shadowStart,
		 shadowPos 	= shadowStep * dither + shadowStart;

	vec3 scatteringSun = vec3(0.0);
	vec3 scatteringSky = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	float LdotV = dot(worldLightVector, worldDir);
	vec2 phase = vec2(HenyeyGreensteinPhase(LdotV, 0.5) * 0.6 + HenyeyGreensteinPhase(LdotV, -0.3) * 0.25 + HenyeyGreensteinPhase(LdotV, 0.85) * 0.15, RayleighPhase(LdotV));

	uint i = 0u;
	while (++i < steps) {
		rayPos += rayStep, shadowPos += shadowStep;

		#if MC_VERSION < 11800
			if (rayPos.y > 256.0) continue;
		#else
			if (rayPos.y > 384.0) continue;
		#endif

		vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;

		vec2 density = CalculateFogDensity(rayPos) * stepLength;

		if (dot(density, vec2(1.0)) < 1e-6) continue; // Faster than maxOf()

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

		vec3 opticalDepth = fogExtinctionCoeff * density;
		vec3 stepTransmittance = fastExp(-opticalDepth);

		vec3 stepScattering = transmittance * oneMinus(stepTransmittance) / maxEps(opticalDepth);
		// stepScattering *= 2.0 * oneMinus(fastExp(-opticalDepth * 4.0)); // Powder Effect

		scatteringSun += fogScatteringCoeff * (density * phase) * sampleShadow * stepScattering;
		scatteringSky += fogScatteringCoeff * density * stepScattering;

		transmittance *= stepTransmittance;

		if (dot(transmittance, vec3(1.0)) < 1e-3) break; // Faster than maxOf()
	}

	vec3 scattering = scatteringSun * 12.0 * directIlluminance;
	scattering += scatteringSky * mix(skyIlluminance * 0.2, directIlluminance * 0.1, wetness * 0.6);
	scattering *= eyeSkylightSmooth;

	return mat2x3(scattering, transmittance);
}

#include "/lib/water/WaterFog.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy) << 1;

    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize * 2.0;
	vec3 screenPos = vec3(screenCoord, readDepth0(screenTexel));

	vec3 viewPos = ScreenToViewSpace(screenPos);
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;

	float dither = BlueNoiseTemporal(screenTexel);

	mat2x3 volFogData = mat2x3(vec3(0.0), vec3(1.0));

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

	scatteringOut = volFogData[0];
	transmittanceOut = volFogData[1];

	// Apply bayer dithering to reduce banding artifacts
	transmittanceOut += (dither - 0.5) * r255;
}