/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#define PASS_SHADOW

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

layout (location = 0) out vec3 shadowcolor0Out;
layout (location = 1) out vec4 shadowcolor1Out;

//======// Input //===============================================================================//

in vec2 texCoord;

// in vec3 viewPos;
in vec3 vectorData; // Minecraft position in water, vertColor in other materials

flat in uint isWater;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

#include "/lib/water/WaterWave.glsl"

//======// Main //================================================================================//
void main() {
	if (isWater == 1u) {
		vec3 waveNormal = CalculateWaterNormal(vectorData.xz);
		shadowcolor1Out.xy = OctEncodeUnorm(waveNormal.xzy);
		shadowcolor1Out.w = 1.0;
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

		if (albedo.a > oms(rcp255)) {
			shadowcolor0Out = albedo.rgb * vectorData;
		} else {
			albedo.a = approxSqrt(approxSqrt(albedo.a));
			shadowcolor0Out = mix(vec3(albedo.a), albedo.rgb * vectorData, albedo.a);
		}

		shadowcolor1Out.w = 0.0;
	}
}
