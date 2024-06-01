
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

flat in float isWater;

flat in mat3 tbnMatrix;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Function //============================================================================//

//======// Main //================================================================================//
void main() {
	if (isWater > 0.5) {
		shadowcolor0Out = vec3(0.8);
		shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2] * 0.5 + 0.5);
	} else {
		vec4 albedo = texture(tex, texCoord);
		if (albedo.a < 0.1) discard;

        if (albedo.a > 254.0 / 255.0) {
			shadowcolor0Out = albedo.rgb * tint;
		} else {
			shadowcolor0Out = mix(vec3(1.0), albedo.rgb * tint, albedo.a);
		}
		shadowcolor1Out.xy = encodeUnitVector(tbnMatrix[2] * 0.5 + 0.5);
	}

	shadowcolor1Out.z = lightmap.y;
}
