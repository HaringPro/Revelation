/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Compute cloud shadow map

--------------------------------------------------------------------------------
*/

#define PASS_CLOUD_SM

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 10 */
out float cloudShadowOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Offset.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

//======// Main //================================================================================//
void main() {
	ivec2 mapTexel = ivec2(gl_FragCoord.xy);

	// Read previous frame data
	cloudShadowOut = texelFetch(colortex10, mapTexel, 0).x;
	bool frameUpdate = cloudShadowOut < EPS || worldTimeChanged;

    // Checkerboard render cloud shadow map
	ivec2 offset = checkerboardOffset4x4[frameCounter % 16];
	if (mapTexel % 4 == offset) {
		vec2 mapCoord = gl_FragCoord.xy * rcp(textureSize(colortex10, 0));
        vec3 rayPos = CloudShadowToWorldPos(mapCoord);
        float cloudShadow = CalculateCloudShadows(rayPos);

		// Accumulate
		float accumFactor = frameUpdate ? 1.0 : 0.125;
		cloudShadowOut = mix(cloudShadowOut, cloudShadow, accumFactor);
	}
}