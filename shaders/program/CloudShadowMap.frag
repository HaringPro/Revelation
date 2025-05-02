/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

    Pass: Compute cloud shadow map

--------------------------------------------------------------------------------
*/

#define PASS_CLOUD_SHADOW_MAP

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 10 */
out float cloudShadowOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Offset.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

//======// Main //================================================================================//
void main() {
	ivec2 mapTexel = ivec2(gl_FragCoord.xy);
	vec2 mapCoord = gl_FragCoord.xy * rcp(cloudShadowSize);

    // Checkerboard render cloud shadow map
	ivec2 offset = checkerboardOffset2x2[frameCounter % 4];
	if (mapTexel % 2 == offset) {
        vec3 rayPos = CloudShadowToWorldPos(mapCoord);
        cloudShadowOut = CalculateCloudShadows(rayPos);
	} else {
		cloudShadowOut = texelFetch(colortex10, mapTexel, 0).x;
	}
}