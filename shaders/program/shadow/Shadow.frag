/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

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

//======// Main //================================================================================//
void main() {
	if (isWater == 1) {
		shadowcolor0Out = vec3(1.0);
		shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2]);
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

        if (albedo.a > 254.0 / 255.0) {
			shadowcolor0Out = albedo.rgb * tint;
		} else {
			shadowcolor0Out = mix(vec3(1.0), albedo.rgb * tint, fastSqrt(albedo.a));
		}
		shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2]);
	}

	shadowcolor1Out.z = lightmap.y;
}
