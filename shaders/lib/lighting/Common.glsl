#if !defined INCLUDE_LIB_LIGHTING_COMMON
#define INCLUDE_LIB_LIGHTING_COMMON

#include "/lib/lighting/BRDF.glsl"

//================================================================================================//

float CalculateFakeBouncedLight(vec3 normal) {
	float bounce = saturate(dot(shadowDirWorld, vec3(0.01, 0.025, 0.01)));

	return approxSqrt(bounce * oms(0.75 * normal.y)) * uniformPhase;
}

float CalculateBlocklightFalloff(float blocklight) {
	blocklight = mix(blocklight, sqr(blocklight), 0.75);
	return blocklight * blocklight * blocklight;
}

#endif // INCLUDE_LIB_LIGHTING_COMMON
