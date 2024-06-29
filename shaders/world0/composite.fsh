#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

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

#define VOLUMETRIC_FOG_SAMPLES 20 // Sample count of volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 24 28 30 40 50 70 100 150 200 300 500]
#define FOG_QUALITY 1 // [0 1]
// #define COLORED_VOLUMETRIC_FOG // Enables volumetric fog stained glass tint
#define TIME_FADE // Reduces fog density at noon

#define FOG_MIE_DENSITY 0.001 // Mie scattering density
#define FOG_RAYLEIGH_DENSITY 0.0004 // Rayleigh scattering density
#define SEA_LEVEL 63.0 // Sea level. [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0 121.0 122.0 123.0 124.0 125.0 126.0 127.0 128.0 129.0 130.0 131.0 132.0 133.0 134.0 135.0 136.0 137.0 138.0 139.0 140.0 141.0 142.0 143.0 144.0 145.0 146.0 147.0 148.0 149.0 150.0 151.0 152.0 153.0 154.0 155.0 156.0 157.0 158.0 159.0 160.0 161.0 162.0 163.0 164.0 165.0 166.0 167.0 168.0 169.0 170.0 171.0 172.0 173.0 174.0 175.0 176.0 177.0 178.0 179.0 180.0 181.0 182.0 183.0 184.0 185.0 186.0 187.0 188.0 189.0 190.0 191.0 192.0 193.0 194.0 195.0 196.0 197.0 198.0 199.0 200.0 201.0 202.0 203.0 204.0 205.0 206.0 207.0 208.0 209.0 210.0 211.0 212.0 213.0 214.0 215.0 216.0 217.0 218.0 219.0 220.0 221.0 222.0 223.0 224.0 225.0 226.0 227.0 228.0 229.0 230.0 231.0 232.0 233.0 234.0 235.0 236.0 237.0 238.0 239.0 240.0 241.0 242.0 243.0 244.0 245.0 246.0 247.0 248.0 249.0 250.0 251.0 252.0 253.0 254.0 255.0]

#define UW_VOLUMETRIC_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]
#define UW_VOLUMETRIC_FOG_SAMPLES 22 // Sample count of underwater volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 22 24 26 28 30 40 50 70 100 150 200 300 500]


const vec2 falloffScale = 1.0 / vec2(12.0, 60.0);

const int shadowMapResolution = 2048; // [1024 2048 4096 8192 16384 32768]
const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

//================================================================================================//

#include "/lib/lighting/ShadowDistortion.glsl"

vec3 WorldPosToShadowPos(in vec3 worldPos) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	return shadowClipPos;
}

#if FOG_QUALITY == 0
	/* Low */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		return exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - 3.0);
	}
#elif FOG_QUALITY == 1
	/* Medium */
	vec2 CalculateFogDensity(in vec3 rayPos) {
		vec2 density = exp2(min((SEA_LEVEL + 16.0 - rayPos.y) * falloffScale, 0.1) - 3.0);

		rayPos *= 0.07;
		rayPos += fogWind;
		float noise = Calculate3DNoise(rayPos) * 3.0;
		noise -= Calculate3DNoise(rayPos * 4.0 + fogWind);

		density.x *= max0(noise * 8.0 - 5.0);

		return density;
	}
#endif

mat2x3 CalculateVolumetricFog(in vec3 worldPos, in vec3 worldDir, in float dither) {	
	mat2x3 fogCoeff = mat2x3(
		vec3(FOG_MIE_DENSITY),
		vec3(0.32, 0.45, 1.0) * FOG_RAYLEIGH_DENSITY
	);

	#ifdef TIME_FADE
		fogCoeff *= max(wetness, sqr(1.0 - timeNoon * 0.85));
	#endif

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

	mat2x3 scatteringSun = mat2x3(0.0);
	vec3   scatteringSky = vec3(0.0);
	vec3   transmittance = vec3(1.0);

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

		if (density.x + density.y < 1e-6) continue; // Faster than maxOf()

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

		vec3 opticalDepth = fogCoeff * density;
		vec3 stepTransmittance = fastExp(-opticalDepth);

		vec3 stepScattering = transmittance * oneMinus(stepTransmittance) / maxEps(opticalDepth);
		// stepScattering *= 2.0 * oneMinus(fastExp(-opticalDepth * 4.0)); // Powder Effect

		scatteringSun[0] += sampleShadow * stepScattering * density.x;
		scatteringSun[1] += sampleShadow * stepScattering * density.y;
		scatteringSky 	 += opticalDepth * stepScattering;

		transmittance *= stepTransmittance;

		if (transmittance.x + transmittance.y + transmittance.z < 1e-4) break; // Faster than maxOf()
	}

	scatteringSun[0] *= fogCoeff[0];
	scatteringSun[1] *= fogCoeff[1];

	float LdotV = dot(worldLightVector, worldDir);
	float miePhase = HenyeyGreensteinPhase(LdotV, 0.7) * 0.45 + HenyeyGreensteinPhase(LdotV, -0.3) * 0.15 + 0.15;
	vec3 scattering = scatteringSun * vec2(miePhase, RayleighPhase(LdotV)) * 20.0 * oneMinus(0.7 * wetness) * directIlluminance;

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
			mat2x3 volFogData = CalculateVolumetricFog(worldPos, worldDir, dither);

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
}