/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Checkerboard render clouds
	Reference: https://www.intel.com/content/dam/develop/external/us/en/documents/checkerboard-rendering-for-real-time-upscaling-on-intel-integrated-graphics.pdf
			   https://developer.nvidia.com/sites/default/files/akamai/gameworks/samples/DeinterleavedTexturing.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2 */
out vec4 cloudOut;

//======// Input //===============================================================================//

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Uniform //=============================================================================//

uniform sampler3D COMBINED_TEXTURE_SAMPLER;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"
#include "/lib/universal/Offset.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/PrecomputedAtmosphericScattering.glsl"

#ifdef AURORA
	#include "/lib/atmosphere/Aurora.glsl"
#endif

#include "/lib/atmosphere/clouds/Render.glsl"

vec3 ScreenToViewVectorRaw(in vec2 screenCoord) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * NDCCoord, gbufferProjectionInverse[3].z));
}

#if defined DISTANT_HORIZONS
	float sampleDepthMax4x4DH(in vec2 coord) {
		// 4x4 pixel neighborhood using textureGather
		vec4 sampleDepth0 = textureGather(dhDepthTex0, coord + vec2( 2.0,  2.0) * viewPixelSize);
		vec4 sampleDepth1 = textureGather(dhDepthTex0, coord + vec2(-2.0,  2.0) * viewPixelSize);
		vec4 sampleDepth2 = textureGather(dhDepthTex0, coord + vec2( 2.0, -2.0) * viewPixelSize);
		vec4 sampleDepth3 = textureGather(dhDepthTex0, coord + vec2(-2.0, -2.0) * viewPixelSize);

		return max(max(maxOf(sampleDepth0), maxOf(sampleDepth1)), max(maxOf(sampleDepth2), maxOf(sampleDepth3)));
	}
#else
	float sampleDepthMax4x4(in vec2 coord) {
		// 4x4 pixel neighborhood using textureGather
		vec4 sampleDepth0 = textureGather(depthtex0, coord + vec2( 2.0,  2.0) * viewPixelSize);
		vec4 sampleDepth1 = textureGather(depthtex0, coord + vec2(-2.0,  2.0) * viewPixelSize);
		vec4 sampleDepth2 = textureGather(depthtex0, coord + vec2( 2.0, -2.0) * viewPixelSize);
		vec4 sampleDepth3 = textureGather(depthtex0, coord + vec2(-2.0, -2.0) * viewPixelSize);

		return max(max(maxOf(sampleDepth0), maxOf(sampleDepth1)), max(maxOf(sampleDepth2), maxOf(sampleDepth3)));
	}
#endif


//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	#ifdef CLOUD_CBR_ENABLED
		ivec2 cloudTexel = screenTexel * CLOUD_CBR_SCALE + cloudCbrOffset[frameCounter % cloudRenderArea];
	#else
		#define cloudTexel screenTexel
	#endif
	vec2 cloudUv = texelToUv(cloudTexel);

	if (
	#ifdef CLOUD_CBR_ENABLED
		#if defined DISTANT_HORIZONS
			min(sampleDepthMax4x4DH(cloudUv), loadDepth0(cloudTexel))
		#else
			sampleDepthMax4x4(cloudUv)
		#endif
	#else
		#if defined DISTANT_HORIZONS
			min(loadDepth0DH(cloudTexel), loadDepth0(cloudTexel))
		#else
			loadDepth0(cloudTexel)
		#endif
	#endif
	> 0.999999) {
		#ifdef CLOUD_CBR_ENABLED
			float dither = R1(frameCounter / cloudRenderArea, texelFetch(noisetex, cloudTexel & 255, 0).a);
		#else
			float dither = BlueNoiseTemporal(cloudTexel);
		#endif

		vec3 viewDir  = ScreenToViewVectorRaw(cloudUv);
		vec3 worldDir = mat3(gbufferModelViewInverse) * viewDir;

		cloudOut = RenderClouds(worldDir, dither);

		// Crepuscular rays
		#ifdef CLOUD_SHADOWS
			vec4 crepuscularRays = RaymarchCrepuscular(worldDir, dither);

			cloudOut.rgb = viewerHeight < cumulusBottomRadius ?
						   cloudOut.rgb * crepuscularRays.a + crepuscularRays.rgb : // Below clouds
						   cloudOut.rgb + crepuscularRays.rgb * cloudOut.a;  // Above clouds
			cloudOut.a *= crepuscularRays.a;
		#endif
	} else {
		cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	}
}