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

/* RENDERTARGETS: 2,3 */
layout (location = 0) out vec4 cloudOut;
layout (location = 1) out float cloudDepth;

//======// Uniform //=============================================================================//

uniform sampler3D atmosCombinedLut;

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

float sampleDepthMax4x4(in sampler2D depthTex, in vec2 coord) {
	// 4x4 pixel neighborhood using textureGather
	vec4 sampleDepth0 = textureGather(depthTex, coord + vec2( 2.0,  2.0) * viewPixelSize);
	vec4 sampleDepth1 = textureGather(depthTex, coord + vec2(-2.0,  2.0) * viewPixelSize);
	vec4 sampleDepth2 = textureGather(depthTex, coord + vec2( 2.0, -2.0) * viewPixelSize);
	vec4 sampleDepth3 = textureGather(depthTex, coord + vec2(-2.0, -2.0) * viewPixelSize);

	return max(max(maxOf(sampleDepth0), maxOf(sampleDepth1)), max(maxOf(sampleDepth2), maxOf(sampleDepth3)));
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	#ifdef CLOUD_CBR_ENABLED
		ivec2 cloudTexel = screenTexel * CLOUD_CBR_SCALE + cloudCbrOffset[frameCounter % cloudRenderArea];
	#else
		#define cloudTexel screenTexel
	#endif
	vec2 cloudUv = texelToUv(cloudTexel);

	cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	cloudDepth = 128e3;

	#ifdef CLOUD_CBR_ENABLED
		float depthMax = sampleDepthMax4x4(depthtex0, cloudUv);
		#if defined DISTANT_HORIZONS
			if (depthMax > 0.999999) depthMax = sampleDepthMax4x4(dhDepthTex0, cloudUv);
		#endif
	#else
		float depthMax = loadDepth0(cloudTexel);
		#if defined DISTANT_HORIZONS
			if (depthMax > 0.999999) depthMax = loadDepth0DH(cloudTexel);
		#endif
	#endif

	if (depthMax > 0.999999 || depthMax < 0.56) {
		#ifdef CLOUD_CBR_ENABLED
			float dither = R1(frameCounter / cloudRenderArea, texelFetch(noisetex, cloudTexel & 255, 0).a);
		#else
			float dither = BlueNoiseTemporal(cloudTexel);
		#endif

		vec3 viewDir  = ScreenToViewVectorRaw(cloudUv);
		vec3 worldDir = mat3(gbufferModelViewInverse) * viewDir;

		cloudOut = RenderClouds(worldDir, dither, cloudDepth);

		// Crepuscular rays
		#ifdef CREPUSCULAR_RAYS
			#ifdef CLOUD_SHADOWS
			if (viewerHeight < cumulusBottomRadius) {
				vec4 crepuscularRays = RaymarchCrepuscular(worldDir, dither);

				cloudOut *= crepuscularRays.a;
				cloudOut.rgb += crepuscularRays.rgb;
			}
			#endif
		#endif
	}
}