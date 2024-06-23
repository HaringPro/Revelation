/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.glsl"

//======// Output //==============================================================================//

layout (location = 0) out vec3 shadowcolor0Out;
layout (location = 1) out vec4 shadowcolor1Out;

//======// Input //===============================================================================//

in vec2 texCoord;
in vec2 lightmap;

in vec3 tint;
in vec3 viewPos;
in vec3 minecraftPos;

flat in uint isWater;

flat in mat3 tbnMatrix;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Function //============================================================================//

#ifdef WATER_CAUSTICS
	uniform sampler2D noisetex;

	uniform float frameTimeCounter;
	uniform float far;

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
			vec3 wavesNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
			vec3 normal = tbnMatrix * wavesNormal;

			vec3 oldPos = viewPos;
			vec3 newPos = oldPos + fastRefract(vec3(0.0, 0.0, -1.0), normal, 1.0 / WATER_REFRACT_IOR) * 2.0;

			float oldArea = dotSelf(dFdx(oldPos)) * dotSelf(dFdy(oldPos));
			float newArea = dotSelf(dFdx(newPos)) * dotSelf(dFdy(newPos));

			float caustics = inversesqrt(oldArea / newArea) * 0.4;

			shadowcolor0Out = vec3(sqrt2(caustics));
			shadowcolor1Out.xy = encodeUnitVector(normal);
			// shadowcolor1Out.w = minecraftPos.y * rcp(512.0) + 0.25;
		#else
			shadowcolor0Out = vec3(0.8);
			shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2]);
		#endif
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

        if (albedo.a > oneMinus(r255)) {
			shadowcolor0Out = albedo.rgb * tint;
		} else {
			albedo.a = fastSqrt(fastSqrt(albedo.a));
			shadowcolor0Out = mix(vec3(albedo.a), albedo.rgb * tint, albedo.a);
		}
		shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2]);
	}

	shadowcolor1Out.z = lightmap.y;
}