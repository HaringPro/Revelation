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

//======// Uniform //=============================================================================//

uniform usampler2D colortex11; // Volumetric Fog, linear depth

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

#include "/lib/lighting/shadow/Common.glsl"

#include "/lib/atmosphere/AtmosphericFog.glsl"
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
	#if defined LOD_MOD
		if (screenPos.z > 1.0 - EPS) {
			screenPos.z = loadDepth0Lod(screenTexel);
			viewPos = ScreenToViewSpaceLod(screenPos);
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;

	float dither = BlueNoiseTemporal(screenTexel);

	mat2x3 volFogData = mat2x3(vec3(0.0), vec3(1.0));

	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			volFogData = RaymarchAtmosphericFog(worldPos, dither, screenPos.z > 1.0 - EPS);
		}
	#endif
	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			volFogData = RaymarchWaterFog(worldPos, dither);
		}
	#endif

	// Temporal reprojection
    vec2 prevCoord = Reproject(screenPos).xy;

    if (saturate(prevCoord) == prevCoord && !worldTimeChanged) {
        uvec4 reprojectedData = texture(colortex11, prevCoord);
		mat2x3 reprojectedFog = UnpackFogData(reprojectedData.rgb);

		float blendWeight = 0.8;
		blendWeight *= exp2(abs(uintBitsToFloat(reprojectedData.a) + viewPos.z) * 32.0 / viewPos.z);

        volFogData[0] = mix(volFogData[0], reprojectedFog[0], blendWeight);
        volFogData[1] = mix(volFogData[1], reprojectedFog[1], blendWeight);
	}

	packedFogData.x = packHalf2x16(volFogData[0].rg);
	packedFogData.y = packUnorm2x16(volFogData[1].rg);
	packedFogData.z = packHalf2x16(vec2(volFogData[0].b, volFogData[1].b));
	packedFogData.w = floatBitsToUint(-viewPos.z);
}