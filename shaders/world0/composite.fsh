#version 450 compatibility

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

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

flat in mat2x3[2] fogCoeff;

//======// Uniform //=============================================================================//

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform vec3 fogWind;

#include "/lib/utility/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"

#include "/lib/atmospherics/Global.inc"
#ifdef CLOUD_SHADOWS
	#include "/lib/atmospherics/Clouds.glsl"
#endif

const vec2 falloffScale = 1.0 / vec2(12.0, 70.0);

#if defined VOXEL_BRANCH
    #include "/lib/voxel/Constants.glsl"
#else
	const int shadowMapResolution = 2048;  // [1024 2048 4096 8192 16384 32768]
	const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;
#endif

//================================================================================================//

#if defined VOXEL_BRANCH
    #include "/lib/voxel/shadow/ShadowDistortion.glsl"
#else
	#include "/lib/lighting/ShadowDistortion.glsl"
#endif

vec3 WorldPosToShadowPos(in vec3 worldPos) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	return shadowClipPos;
}

#if FOG_QUALITY == 0
	/* Low */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		return exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - 2.0);
	}
#elif FOG_QUALITY == 1
	/* Medium */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		vec2 density = exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - 2.0);

		rayPos *= 0.07;
		rayPos += fogWind;
		float noise = Calculate3DNoise(rayPos) * 3.0;
		noise -= Calculate3DNoise(rayPos * 4.0 + fogWind);

		density.x *= saturate(noise * 8.0 - 6.0) * 2.0;

		return density;
	}
#endif

mat2x3 AirVolumetricFog(in vec3 worldPos, in vec3 worldDir, in float dither) {
	float rayLength = min(length(worldPos), far);

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
	vec2 phase = vec2(HenyeyGreensteinPhase(LdotV, 0.7) * 0.45 + HenyeyGreensteinPhase(LdotV, -0.3) * 0.15 + 0.15, RayleighPhase(LdotV));

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

		#ifdef CLOUD_SHADOWS
			float cloudShadow = CalculateCloudShadow(rayPos);
			sampleShadow *= cloudShadow * cloudShadow * cloudShadow;
		#endif

		vec3 opticalDepth = fogCoeff[0] * density;
		vec3 stepTransmittance = fastExp(-opticalDepth);

		vec3 stepScattering = transmittance * oneMinus(stepTransmittance) / maxEps(opticalDepth);
		// stepScattering *= 2.0 * oneMinus(fastExp(-opticalDepth * 4.0)); // Powder Effect

		scatteringSun += fogCoeff[1] * (density * phase) * sampleShadow * stepScattering;
		scatteringSky += fogCoeff[1] * density * stepScattering;

		transmittance *= stepTransmittance;

		if (dot(transmittance, vec3(1.0)) < 1e-4) break; // Faster than maxOf()
	}

	vec3 scattering = scatteringSun * 16.0 * directIlluminance;
	scattering += scatteringSky * 0.6 * skyIlluminance;
	scattering *= eyeSkylightFix;

	return mat2x3(scattering, transmittance);
}

#include "/lib/water/WaterFog.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy) * 2;

	vec3 screenPos = vec3(screenCoord, sampleDepth(screenTexel));
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	float dither = BlueNoiseTemporal(screenTexel);

	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			mat2x3 volFogData = AirVolumetricFog(worldPos, worldDir, dither);

			scatteringOut = volFogData[0];
			transmittanceOut = volFogData[1];
		}
	#endif

	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			mat2x3 volFogData = UnderwaterVolumetricFog(worldPos, worldDir, dither);

			scatteringOut = volFogData[0];
			transmittanceOut = volFogData[1];
		}
	#endif

	// Apply bayer dithering to reduce banding artifacts
	transmittanceOut += (dither - 0.5) * r255;
}