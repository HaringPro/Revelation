/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Compute Sky-View LUT, cloud shadow map

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

/* RENDERTARGETS: 5,10 */
layout (location = 0) out vec3 skyViewOut;
layout (location = 1) out float cloudShadowOut;

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
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    // Render sky-view LUTs
	if (screenTexel.y >= skyViewRes.y) {
		// With clouds
		vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector) * skyIntensity;

		#ifdef CLOUDS
			float cloudDepth;
            vec4 cloudData = RenderClouds(worldDir/* , skyViewOut */, 0.5, cloudDepth);
            skyViewOut = skyViewOut * cloudData.a + cloudData.rgb;
        #endif
	} else {
		// Raw
		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector) * skyIntensity;
	}

    #ifdef CLOUD_SHADOWS

    // Checkerboard render cloud shadow map
	ivec2 offset = checkerboardOffset2x2[frameCounter % 4];
	if (screenTexel % 2 == offset) {
        vec3 rayPos = CloudShadowToWorldPos(screenCoord);
        cloudShadowOut = CalculateCloudShadows(rayPos);
	} else {
		cloudShadowOut = texelFetch(colortex10, screenTexel, 0).x;
	}

    #endif
}

#endif