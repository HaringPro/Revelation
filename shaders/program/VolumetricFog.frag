/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Compute and accumulate volumetric fog

--------------------------------------------------------------------------------
*/

#define PASS_VOLUMETRIC_FOG

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 11 */
out uvec4 packedFogData;

//======// Uniform //=============================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/lighting/shadow/Common.glsl"

#include "/lib/atmosphere/Common.glsl"

#if defined DIMENSION_NETHER
#include "/lib/atmosphere/NetherFog.glsl"
#else
#include "/lib/atmosphere/AtmosphericFog.glsl"
#endif

#include "/lib/water/WaterFog.glsl"

mat2x3 UnpackFogData(uvec2 data) {
	return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
}

//======// Main //================================================================================//
void main() {
	ivec2 texelPos = ivec2(gl_FragCoord.xy * 2.0);

	vec2 screenCoord = gl_FragCoord.xy * scaledTexelSize * 2.0;
	vec3 screenPos = vec3(screenCoord, loadDepth0(texelPos));

	vec3 viewPos = ScreenToViewPosRaw(screenPos);
	#if defined LOD_MOD
        bool lodMask = screenPos.z > 1.0 - EPS;
		if (lodMask) {
			screenPos.z = loadDepth0Lod(texelPos);
			viewPos = ScreenToViewPosRawLod(screenPos);
		}
	#endif

	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

	float dither = BlueNoise(texelPos, frameCounter);

	mat2x3 volFogData = mat2x3(vec3(0.0), vec3(1.0));

    #if defined DIMENSION_NETHER
		volFogData = RaymarchNetherFog(gbufferModelViewInverse[3].xyz, worldPos, dither, 24);
	#elif defined VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			volFogData = RaymarchAtmosphericFog(gbufferModelViewInverse[3].xyz, worldPos, dither, VF_MAX_SAMPLES);
		}
	#endif
	#ifdef UW_VOLUMETRIC_FOG
		if (isEyeInWater == 1) {
			volFogData = RaymarchWaterFog(worldPos - gbufferModelViewInverse[3].xyz, dither);
		}
	#endif

	// Temporal reprojection
	vec3 prevViewPos = worldPos + cameraMovement * step(0.56, screenPos.z);
	prevViewPos = transMAD(gbufferPreviousModelView, prevViewPos);
	vec3 prevNdcPos = projMAD(gbufferPreviousProjection, prevViewPos) * rcp(-prevViewPos.z);
    #if defined LOD_MOD
        if (lodMask) {
            prevNdcPos = projMAD(lodPrevProjection, prevViewPos) * rcp(-prevViewPos.z);
        }
    #endif
	vec2 prevCoord = prevNdcPos.xy * 0.5 + 0.5;

	if (saturate(prevCoord) == prevCoord && !historyReset) {
        float rand = InterleavedGradientNoise(gl_FragCoord.xy, frameCounter);
        ivec2 sampleTexel = StochasticBilinear(prevCoord * scaledViewSize, rand);

		uvec3 reprojectedData = texelFetch(colortex11, sampleTexel >> 1, 0).xyz;
		mat2x3 reprojectedFog = UnpackFogData(reprojectedData.xy);

		float blendWeight = 0.9;
		blendWeight *= exp2(abs(uintBitsToFloat(reprojectedData.z) + viewPos.z) * 32.0 / viewPos.z);

		volFogData[0] = mix(volFogData[0], reprojectedFog[0], blendWeight);
		volFogData[1] = mix(volFogData[1], reprojectedFog[1], blendWeight);
	}

	packedFogData.x = EncodeRGBE8U(volFogData[0]);
	packedFogData.y = EncodeRGBE8U(volFogData[1]);
	packedFogData.z = floatBitsToUint(-viewPos.z);
}
