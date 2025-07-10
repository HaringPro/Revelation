/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Compute Sky-View LUT

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#if defined VERTEX_SHADER

//======// Output //==============================================================================//

noperspective out vec2 screenCoord;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;
}

#else

#define PASS_SKY_VIEW

//======// Output //==============================================================================//

/* RENDERTARGETS: 5 */
out vec3 skyViewOut;

//======// Input //===============================================================================//

noperspective in vec2 screenCoord;

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

//======// Main //================================================================================//
void main() {
	ivec2 viewTexel = ivec2(gl_FragCoord.xy);

	// Read previous frame data
	skyViewOut = texelFetch(colortex5, viewTexel, 0).rgb;
	bool frameUpdate = skyViewOut.x < EPS || worldTimeChanged;

    // Checkerboard render
	ivec2 offset = checkerboardOffset4x4[frameCounter % 16];
	if (viewTexel % 4 == offset || frameUpdate) {
		// Render sky-view LUTs
		vec3 skyViewLuts = vec3(0.0);
		if (viewTexel.y < skyViewRes.y) {
			// Raw
			vec3 worldDir = ToSkyViewLutParams(screenCoord);
			skyViewLuts = GetSkyRadiance(worldDir, worldSunVector) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;
		} else {
			// With clouds
			vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
			skyViewLuts = GetSkyRadiance(worldDir, worldSunVector) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;

			#ifdef CLOUDS
				float cloudDepth;
				vec4 cloudData = RenderClouds(worldDir, 0.5, cloudDepth);
				skyViewLuts = skyViewLuts * cloudData.a + cloudData.rgb;
			#endif
		}

		// Accumulate
		float accumFactor = frameUpdate ? 1.0 : 0.25;
		skyViewOut = mix(skyViewOut, skyViewLuts, accumFactor);
	}
}

#endif