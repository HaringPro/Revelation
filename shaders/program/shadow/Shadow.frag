/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
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

#ifdef RSM_ENABLED
	in float skyLightmap;
	flat in vec3 flatNormal;
#endif

// in vec3 viewPos;
in vec3 vectorData; // Minecraf position in water, vertColor in other materials

flat in uint isWater;

// flat in mat3 tbnMatrix;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Main //================================================================================//
void main() {
	if (isWater == 1u) {
		// #ifdef WATER_CAUSTICS
			// float dither = BlueNoiseTemporal(ivec2(gl_FragCoord.xy));
			// vec3 lightVector = fastRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR);
			// float caustics = CalculateWaterCaustics(vectorData, lightVector, dither);

			// shadowcolor0Out = vec3(caustics);
			// #ifdef RSM_ENABLED
			// 	shadowcolor1Out.xy = OctEncodeUnorm(normal);
			// #endif
			shadowcolor1Out.w = vectorData.y * rcp(512.0) + 0.25;
		// #else
		// 	shadowcolor0Out = vec3(0.8);
			// #ifdef RSM_ENABLED
			// 	shadowcolor1Out.xy = OctEncodeUnorm(tbnMatrix[2]);
			// #endif
		// #endif
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

        if (albedo.a > oms(r255)) {
			shadowcolor0Out = albedo.rgb * vectorData;
		} else {
			albedo.a = approxSqrt(approxSqrt(albedo.a));
			shadowcolor0Out = mix(vec3(albedo.a), albedo.rgb * vectorData, albedo.a);
		}

		#ifdef RSM_ENABLED
			shadowcolor1Out.xy = OctEncodeUnorm(flatNormal);
		#endif
	}

	#ifdef RSM_ENABLED
		shadowcolor1Out.z = skyLightmap;
	#endif
}