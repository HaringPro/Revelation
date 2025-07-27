/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute volumetric fog, reprojection

--------------------------------------------------------------------------------
*/

#define PASS_VOLUMETRIC_FOG

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 11 */
out uvec4 packedFogData;

//======// Input //===============================================================================//

flat in mat2x3 fogExtinctionCoeff;
flat in mat2x3 fogScatteringCoeff;

//======// Uniform //=============================================================================//

uniform usampler2D colortex11; // Volumetric Fog, linear depth

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform float biomeSandstorm;
uniform float biomeSnowstorm;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

// x: Mie y: Rayleigh
const vec2 falloffScale = -1.0 / vec2(12.0, 36.0);

const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

//================================================================================================//

#include "/lib/lighting/ShadowDistortion.glsl"

#if VF_NOISE_QUALITY == 0
	/* Low */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		return exp2(abs(VF_HEIGHT - rayPos.y) * falloffScale + vec2((biomeSandstorm + biomeSnowstorm) * 2.0, 0.0));
	}
#elif VF_NOISE_QUALITY == 1
	/* Medium */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		vec2 density = exp2(abs(VF_HEIGHT - rayPos.y) * falloffScale + vec2((biomeSandstorm + biomeSnowstorm) * 2.0, 0.0));

		vec3 windOffset = vec3(0.07, 0.04, 0.05) * worldTimeCounter;

		rayPos *= 0.05;
		rayPos -= windOffset;
		float noise = Calculate3DNoise(rayPos) * 3.0;
		noise -= Calculate3DNoise(rayPos * 4.0 - windOffset);

		density.x *= saturate(noise * 8.0 - 6.0) * (1.5 + biomeSandstorm + biomeSnowstorm);

		return density;
	}
#endif

#ifndef CLOUD_SHADOWS
	#undef VF_CLOUD_SHADOWS
#endif

mat2x3 RaymarchAtmosphericFog(in vec3 worldPos, in float dither) {
	#if defined DISTANT_HORIZONS
		#define far float(dhRenderDistance)
		uint steps = VF_MAX_SAMPLES << 1u;
	#else
		uint steps = VF_MAX_SAMPLES;
	#endif

	vec3 rayStart = gbufferModelViewInverse[3].xyz;

	float rayLength = sdot(worldPos);
	float norm = inversesqrt(rayLength);
	rayLength = min(rayLength * norm, far);

	vec3 worldDir = worldPos * norm;

	// Adaptive step count
	steps = min(steps, uint(float(steps) * 0.4 + rayLength * 0.1));

	float stepLength = rayLength * rcp(float(steps));

	vec3 rayStep = worldDir * stepLength;
	vec3 rayPos = rayStart + rayStep * dither + cameraPosition;

	vec3 shadowViewStart = transMAD(shadowModelView, rayStart);
	vec3 shadowStart = projMAD(shadowProjection, shadowViewStart);

	vec3 shadowViewStep = mat3(shadowModelView) * rayStep;
	vec3 shadowStep = diagonal3(shadowProjection) * shadowViewStep;
	vec3 shadowPos = shadowStart + shadowStep * dither;

	#ifdef VF_CLOUD_SHADOWS
		const float projectionScale = rcp(CLOUD_SHADOW_DISTANCE) * 0.5;

		shadowViewStart.xy *= projectionScale;
		shadowViewStep.xy *= projectionScale;
		vec2 cloudShadowPos = shadowViewStart.xy + shadowViewStep.xy * dither + 0.5;
	#endif

	float LdotV = dot(worldLightVector, worldDir);
	vec2 phase = vec2(HenyeyGreensteinPhase(LdotV, 0.65) * 0.75 + HenyeyGreensteinPhase(LdotV, -0.25) * 0.25, RayleighPhase(LdotV));
	phase.x = mix(uniformPhase, phase.x, 0.75); // Trick to fit the multi-scattering

	float uniformFog = 0.0 / far;

	vec3 scatteringSun = vec3(0.0);
	vec3 scatteringSky = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	for (uint i = 0u; i < steps; ++i, rayPos += rayStep, shadowPos += shadowStep) {
		vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;

		vec2 stepFogmass = CalculateFogDensity(rayPos) + uniformFog;
		stepFogmass *= stepLength;

		if (dot(stepFogmass, vec2(1.0)) < 1e-5) continue; // Faster than maxOf()

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
			cloudShadowPos += shadowViewStep.xy;

			// vec2 cloudShadowCoord = DistortCloudShadowPos(cloudShadowPos);
			float cloudShadow = texture(colortex10, cloudShadowPos).x;
			sampleShadow *= cloudShadow * cloudShadow;
		#endif

		vec3 opticalDepth = fogExtinctionCoeff * stepFogmass;
		vec3 stepTransmittance = fastExp(-opticalDepth);

		vec3 stepScattering = transmittance * oms(stepTransmittance) / maxEps(opticalDepth);

		scatteringSun += fogScatteringCoeff * (stepFogmass * phase) * sampleShadow * stepScattering;
		scatteringSky += fogScatteringCoeff * stepFogmass * stepScattering;

		transmittance *= stepTransmittance;

		if (dot(transmittance, vec3(1.0)) < 1e-3) break; // Faster than maxOf()
	}

	vec3 directIlluminance = loadDirectIllum();
	vec3 skyIlluminance = loadSkyIllum();

	vec3 scattering = scatteringSun * directIlluminance;
	scattering += scatteringSky * uniformPhase * skyIlluminance;
	scattering *= eyeSkylightSmooth;

	return mat2x3(scattering, transmittance);
}

#include "/lib/water/WaterFog.glsl"

mat2x3 UnpackFogData(in uvec3 data) {
	vec2 unpackedZ = unpackHalf2x16(data.z);
	vec3 scattering = vec3(unpackHalf2x16(data.x), unpackedZ.x);
	vec3 transmittance = vec3(unpackUnorm2x16(data.y), unpackedZ.y);
	return mat2x3(scattering, transmittance);
}

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

	mat2x3 volFogData = mat2x3(vec3(0.0), vec3(1.0));

	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			volFogData = RaymarchAtmosphericFog(worldPos, dither);
		}
	#endif
	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			volFogData = RaymarchWaterFog(worldPos, dither);
		}
	#endif

	// Temporal reprojection
    vec2 prevCoord = Reproject(screenPos).xy;

    if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
        uvec4 reprojectedData = texture(colortex11, prevCoord);
		mat2x3 reprojectedFog = UnpackFogData(reprojectedData.rgb);

		float blendWeight = 0.75;
		blendWeight *= exp2(abs(uintBitsToFloat(reprojectedData.a) + viewPos.z) * 32.0 / viewPos.z);

        volFogData[0] = mix(volFogData[0], reprojectedFog[0], blendWeight);
        volFogData[1] = mix(volFogData[1], reprojectedFog[1], blendWeight);
	}

	packedFogData.x = packHalf2x16(volFogData[0].rg);
	packedFogData.y = packUnorm2x16(volFogData[1].rg);
	packedFogData.z = packHalf2x16(vec2(volFogData[0].b, volFogData[1].b));
	packedFogData.w = floatBitsToUint(-viewPos.z);
}