/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

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
in vec3 vectorData; // Minecraf position in water, tint in other materials

flat in uint isWater;

// flat in mat3 tbnMatrix;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#ifdef WATER_CAUSTICS
	uniform sampler2D noisetex;

	uniform vec3 worldLightVector;

	uniform float frameTimeCounter;

//======// Function //============================================================================//

	#include "/lib/water/WaterWave.glsl"

	vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
		float NdotD = dot(normal, dir);
		float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
		if (k < 0.0) return vec3(0.0);

		return dir * eta - normal * (sqrt(k) + NdotD * eta);
	}
#endif

//======// Main //================================================================================//
void main() {
	if (isWater == 1u) {
		#ifdef WATER_CAUSTICS
			vec3 waterNormal = CalculateWaterShadowNormal(vectorData.xz - vectorData.y);

			vec3 oldPos = vectorData;
			vec3 newPos = oldPos + fastRefract(worldLightVector, waterNormal.xzy, 1.0 / WATER_REFRACT_IOR);

			float oldArea = dotSelf(dFdx(oldPos)) * dotSelf(dFdy(oldPos));
			float newArea = dotSelf(dFdx(newPos)) * dotSelf(dFdy(newPos));

			float caustics = inversesqrt(oldArea / newArea);

			shadowcolor0Out = vec3(approxSqrt(saturate(caustics * 0.5 + 0.1)));
			// #ifdef RSM_ENABLED
			// 	shadowcolor1Out.xy = encodeUnitVector(normal);
			// #endif
			shadowcolor1Out.w = vectorData.y * rcp(512.0) + 0.25;
		#else
			shadowcolor0Out = vec3(0.8);
			// #ifdef RSM_ENABLED
			// 	shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2]);
			// #endif
		#endif
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

        if (albedo.a > oneMinus(r255)) {
			shadowcolor0Out = albedo.rgb * vectorData;
		} else {
			albedo.a = approxSqrt(approxSqrt(albedo.a));
			shadowcolor0Out = mix(vec3(albedo.a), albedo.rgb * vectorData, albedo.a);
		}

		#ifdef RSM_ENABLED
			shadowcolor1Out.xy = encodeUnitVector(flatNormal);
		#endif
	}

	#ifdef RSM_ENABLED
		shadowcolor1Out.z = skyLightmap;
	#endif
}