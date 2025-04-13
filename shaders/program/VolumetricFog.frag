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

uniform vec3 fogWind;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

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

mat2x3 AirVolumetricFog(in vec3 worldPos, in float dither, in bool skyMask) {
	#if defined DISTANT_HORIZONS
		#define far float(dhRenderDistance)
		const uint steps = VOLUMETRIC_FOG_SAMPLES << 1u;
	#else
		const uint steps = VOLUMETRIC_FOG_SAMPLES;
	#endif
	const float rSteps = 1.0 / float(steps);

	const float toExp6 = 2.58497;

	vec3 rayStart = gbufferModelViewInverse[3].xyz;

	float rayLength = sdot(worldPos);
	float norm = inversesqrt(rayLength);
	rayLength *= norm;
	vec3 worldDir = worldPos * norm;

	float skyUniformFog = 0.0;
	if (skyMask) {
	#ifdef VF_CLOUD_SHADOWS
		if (eyeAltitude > CLOUD_CU_ALTITUDE || (worldDir.y < 0.0 && eyeAltitude < 0.0)) {
			return mat2x3(vec3(0.0), vec3(1.0));
		}

		const float cumulusTopRadius = planetRadius + cumulusMaxAltitude;
		vec2 intersection = RaySphericalShellIntersection(viewerHeight, worldDir.y, planetRadius, cumulusTopRadius);
		// float rayLengthMax = (cumulusTopRadius - viewerHeight) / max(0.125, worldDir.y);

		if (intersection.y < 0.0) return mat2x3(vec3(0.0), vec3(1.0));

		rayLength = clamp(intersection.y - intersection.x, EPS, 4096.0);
		rayStart += worldDir * intersection.x;
	#else
		rayLength = far;
	#endif

		skyUniformFog = 32.0 / rayLength;
	}

	vec3 rayStep = worldDir * rayLength;

	vec3 shadowStart = WorldPosToShadowPos(rayStart),
		 shadowStep  = mat3(shadowModelView) * rayStep;
	     shadowStep = diagonal3(shadowProjection) * shadowStep;

	rayLength *= toExp6 * 0.2 * rSteps;
	rayStart += cameraPosition;

	float LdotV = dot(worldLightVector, worldDir);
	vec2 phase = vec2(HG_DrainePhase(LdotV, 25.0), RayleighPhase(LdotV));
	phase.x = mix(uniformPhase, phase.x, 0.65); // Trick to fit the multi-scattering

	vec3 scatteringSun = vec3(0.0);
	vec3 scatteringSky = vec3(0.0);
	vec3 transmittance = vec3(1.0);

	for (uint i = 0u; i < steps; ++i) {
		float stepExp = exp2(toExp6 * (float(i) + dither) * rSteps);
		float stepLength = (stepExp - 1.0) * 0.2; // Normalize to [0, 1]

		vec3 rayPos = rayStart + stepLength * rayStep;
		vec3 shadowPos = shadowStart + stepLength * shadowStep;

		vec3 shadowScreenPos = DistortShadowSpace(shadowPos) * 0.5 + 0.5;

		vec2 stepFogmass = CalculateFogDensity(rayPos) + skyUniformFog;
		stepFogmass *= stepExp * rayLength;

		if (dot(stepFogmass, vec2(1.0)) < 1e-4) continue; // Faster than maxOf()

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
			vec2 cloudShadowCoord = WorldToCloudShadowCoord(rayPos - cameraPosition);
			float cloudShadow = texture(colortex10, cloudShadowCoord).x;
			sampleShadow *= cloudShadow * cloudShadow;
		#endif

		vec3 opticalDepth = fogExtinctionCoeff * stepFogmass;
		vec3 stepTransmittance = exp2(-opticalDepth);

		vec3 stepScattering = transmittance * oms(stepTransmittance) / maxEps(opticalDepth);
		// stepScattering *= 2.0 * oms(fastExp(-opticalDepth * 4.0)); // Powder Effect

		scatteringSun += fogScatteringCoeff * (stepFogmass * phase) * sampleShadow * stepScattering;
		scatteringSky += fogScatteringCoeff * stepFogmass * stepScattering;

		transmittance *= stepTransmittance;

		if (dot(transmittance, vec3(1.0)) < 1e-3) break; // Faster than maxOf()
	}

	vec3 directIlluminance = loadDirectIllum();
	vec3 skyIlluminance = loadSkyIllum();

	vec3 scattering = scatteringSun * directIlluminance;
	scattering += scatteringSky * uniformPhase * mix(skyIlluminance, directIlluminance * rPI, wetness * 0.4 + 0.2);
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
			volFogData = AirVolumetricFog(worldPos, dither, screenPos.z > 0.999999);
		}
	#endif
	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			volFogData = UnderwaterVolumetricFog(worldPos, dither);
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