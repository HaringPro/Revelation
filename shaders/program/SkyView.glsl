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

flat out vec3 directIlluminance;
flat out vec3 skyIlluminance;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec2 vaUV0;

//======// Uniform //=============================================================================//

uniform sampler2D colortex4; // Global illuminances

//======// Main //================================================================================//
void main() {
    gl_Position = vec4(vaPosition * 2.0 - 1.0, 1.0);
	screenCoord = vaUV0;

	directIlluminance = loadDirectIllum();
	skyIlluminance = loadSkyIllum();
}

#else

#define PASS_SKY_VIEW

//======// Output //==============================================================================//

/* RENDERTARGETS: 5,10 */
layout (location = 0) out vec3 skyViewOut;
layout (location = 1) out float cloudShadowOut;

//======// Input //===============================================================================//

noperspective in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler3D COMBINED_TEXTURE_SAMPLER;

uniform float nightVision;
uniform float wetness;
uniform float eyeAltitude;
uniform float far;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 worldSunVector;
uniform vec3 worldLightVector;
uniform vec3 cameraPosition;
uniform vec3 lightningShading;

uniform float worldTimeCounter;

#ifdef CLOUD_SHADOWS
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
#if defined DISTANT_HORIZONS
uniform int dhRenderDistance;
#endif
#endif

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/PrecomputedAtmosphericScattering.glsl"

#ifdef AURORA
	#include "/lib/atmosphere/Aurora.glsl"
#endif

#include "/lib/atmosphere/clouds/Render.glsl"

#ifdef CLOUD_SHADOWS
    #include "/lib/atmosphere/clouds/Shadows.glsl"
#endif

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    // Render sky-view LUTs
	if (screenTexel.y >= skyViewRes.y) {
		// With clouds
		vec3 worldDir = ToSkyViewLutParams(screenCoord - vec2(0.0, 0.5));
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector) * skyIntensity;

		#ifdef CLOUDS
            vec4 cloudData = RenderClouds(worldDir/* , skyViewOut */, 0.5);
            skyViewOut = skyViewOut * cloudData.a + cloudData.rgb;
        #endif
	} else {
		// Raw
		vec3 worldDir = ToSkyViewLutParams(screenCoord);
		skyViewOut = GetSkyRadiance(worldDir, worldSunVector) * skyIntensity;
	}

    // Render cloud shadow map
    #ifdef CLOUD_SHADOWS
        vec3 rayPos = CloudShadowToWorldCoord(screenCoord);
        cloudShadowOut = CalculateCloudShadows(rayPos);
    #endif
}

#endif