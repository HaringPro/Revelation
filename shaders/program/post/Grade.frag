/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Post-processing compositing

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define TONE_MAPPER AgX_Minimal // [None AcademyFit AcademyFull AgX_Minimal AgX_Full Lottes GT GT7]

#define GAMMA_CORRECTION 2.2 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0]

#define BLOOM_BLENDING_MODE 1 // [0 1 2]
#define BLOOM_INTENSITY 1.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0 20.0]
#define BLOOMY_FOG_INTENSITY 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

#define PURKINJE_SHIFT
// #define PURKINJE_SHIFT_NOISE
#define PURKINJE_SHIFT_STRENGTH 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define PURKINJE_SHIFT_R 0.56 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
#define PURKINJE_SHIFT_G 0.78 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
#define PURKINJE_SHIFT_B 1.0  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]

// #define VIGNETTE_ENABLED
#define VIGNETTE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]
#define VIGNETTE_ROUNDNESS 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0 5.0]

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 color; // Tonemapped output

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

const vec2 bloomTileOffset[6] = vec2[6](
	vec2(0.0000, 0.0000),
	vec2(0.0000, 0.5000),
	vec2(0.2500, 0.5000),
	vec2(0.2500, 0.6250),
	vec2(0.3125, 0.6250),
	vec2(0.3150, 0.6563)
);

void CombineBloomAndFog(inout vec3 scene, ivec2 texel, float exposure) {
	vec3 bloomData = vec3(0.0);
	vec2 screenCoord = texelToUv(texel);

	float weight = 1.0;
	float sumWeight = 0.0;

	vec2 upscalingCoord = screenCoord;
	for (uint i = 0u; i < 6u; ++i) {
		upscalingCoord *= 0.5;
    	vec2 sampleCoord = upscalingCoord + bloomTileOffset[i];
		sampleCoord += viewPixelSize * float(i * 8);
		vec3 sampleTile = textureBicubic(colortex4, sampleCoord).rgb;

		bloomData += sampleTile * weight;
		sumWeight += weight;
		weight *= 0.9;
	}

	bloomData *= rcp(sumWeight);

	float bloomIntensity = BLOOM_INTENSITY * 0.1;

	#ifdef BLOOMY_FOG
		float fogMask = texture(colortex0, screenCoord + taaJitter * 0.5).w;
		bloomIntensity = max(bloomIntensity, fogMask * BLOOMY_FOG_INTENSITY);
	#endif

	// Exposure adaptation
	bloomIntensity /= max(exposure, 1.0) + 1.0;

	#if BLOOM_BLENDING_MODE == 0
		scene += bloomData * bloomIntensity;
	#elif BLOOM_BLENDING_MODE == 1
		scene = mix(scene, bloomData, bloomIntensity);
	#else
		scene = (scene + bloomData * bloomIntensity) / (1.0 + bloomIntensity * 0.5);
	#endif

	if (rainStrength > 1e-2) {
		float rainAlpha = texture(colortex6, screenCoord).a;
		rainAlpha = oms(rainAlpha) * RAIN_VISIBILITY;
		scene = scene * oms(rainAlpha) + bloomData * rainAlpha * 1.25;
	}
}

// See section 3.4 of http://www.diva-portal.org/smash/get/diva2:24136/FULLTEXT01.pdf
vec3 ScotopicVision(vec3 color, float exposure) {
	const vec3 rodResponse = vec3(0.05, 0.55, 0.60);
	const vec3 tint = vec3(PURKINJE_SHIFT_R, PURKINJE_SHIFT_G, PURKINJE_SHIFT_B);

	vec3 xyz = color * sRGB_2_XYZ;
	vec3 scotopic = xyz * max0(1.33 * (1.0 + (xyz.y + xyz.z) / xyz.x) - 1.68);

	float rodLuminance = dot(scotopic * XYZ_2_sRGB, rodResponse);
	float mesopicFactor = saturate(log2(1.0 + exposure) / (2.0 + 4.0 * rodLuminance));

	#ifdef PURKINJE_SHIFT_NOISE
		rodLuminance *= 0.5 + SampleStbnVec1(ivec2(gl_GlobalInvocationID.xy), frameCounter);
	#endif

	return mix(color, rodLuminance * tint, PURKINJE_SHIFT_STRENGTH * mesopicFactor);
}

vec3 None(vec3 x) {
	return x;
}

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
// https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 Lottes(vec3 x) {
	x *= 2.0;

	const vec3 a      = vec3(1.35);
	const vec3 d      = vec3(0.92);
	const vec3 hdrMax = vec3(8.0);
	const vec3 midIn  = vec3(0.2);
	const vec3 midOut = vec3(0.3);

	const vec3 ad = a * d;
	const vec3 curvedMidIn = pow(midIn, a);
	const vec3 curvedHdrMax = pow(hdrMax, a);
	const vec3 b = -curvedMidIn + curvedHdrMax * midOut;
	const vec3 c = pow(hdrMax, ad) * curvedMidIn - curvedHdrMax * pow(midIn, ad) * midOut;

	return sRGBToLinear(pow(x, a) * (pow(hdrMax, ad) - pow(midIn, ad)) * midOut / (pow(x, ad) * b + c));
}

#include "/lib/post/ACES.glsl"
#include "/lib/post/AgX.glsl"
#include "/lib/post/GT.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);

 	#if EXPOSURE_MODE == MANUAL
		float exposure = exp2(-MANUAL_EV);
	#else
		float exposure = exposure.value;
	#endif

	#ifdef MOTION_BLUR
		color = texelFetch(colortex0, texelPos, 0).rgb;
	#else
		color = texelFetch(colortex1, texelPos, 0).rgb;
	#endif

	// Bloom and fog
	#ifdef BLOOM
		CombineBloomAndFog(color, texelPos, exposure);
	#endif

	// Debug sky environment map
	#ifdef DEBUG_SKY_MAP
		if (all(lessThan(texelPos, textureSize(skyMapTex, 0)))) {
			color = texelFetch(skyMapTex, texelPos, 0).rgb;
		}
	#endif

	#ifdef DEBUG_ATMOSPHERE_LUTS
		ivec2 tempTexel = texelPos;
		if (all(lessThan(tempTexel, textureSize(skyViewTex, 0)))) {
			color = DecodeRGBE8(texelFetch(skyViewTex, tempTexel, 0));
		}
		tempTexel.x -= textureSize(skyViewTex, 0).x;
		if (clamp(tempTexel, ivec2(0), textureSize(tLutTex, 0) - 1) == tempTexel) {
			color = texelFetch(tLutTex, tempTexel, 0).rgb * 64.0;
		}
		tempTexel.x -= textureSize(tLutTex, 0).x;
		if (clamp(tempTexel, ivec2(0), textureSize(msLutTex, 0) - 1) == tempTexel) {
			color = texelFetch(msLutTex, tempTexel, 0).rgb * 512.0;
		}
	#endif

	// Apply exposure
	color *= exposure;

	// Purkinje shift
	#ifdef PURKINJE_SHIFT
		color = ScotopicVision(color, exposure);
	#endif

	// Vignetting
	#ifdef VIGNETTE_ENABLED
		vec2 ndcCoord = texelToUv(texelPos) * 2.0 - 1.0;
		ndcCoord.x *= mix(1.0, aspectRatio, VIGNETTE_ROUNDNESS);
		color *= exp2(-0.5 * VIGNETTE_STRENGTH * sdot(ndcCoord));
	#endif

	// Apply DRT
	{
		// Working to DRT space
		// color *= sRGB_2_Rec2020;

		// Tone mapping
		color = TONE_MAPPER(color);

		// DRT to working space
		// color *= Rec2020_2_sRGB;

		// Working to display space
		color *= Rec2020_2_sRGB;
		color = saturate(pow(color, vec3(1.0 / GAMMA_CORRECTION)));
	}

	// Debug tone mapping plot
	#ifdef DEBUG_TONE_MAPPING_PLOT
		const float scale = 1.5;

		vec2 uv = texelToUv(texelPos) * vec2(aspectRatio, 1.0) * scale;
		float plot = smoothstep(0.0, scale * viewPixelSize.y, abs(uv.y - TONE_MAPPER(vec3(uv.x)).x));

		// Show LDR range
		color = vec3(0.25) * step(uv.x, 1.0);
		color = mix(vec3(1.0), color, plot);
	#endif
}