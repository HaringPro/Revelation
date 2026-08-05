// Keep Voxy patch path stable: do not emit #extension from shared includes.
#define INCLUDE_UTILITY_COMPAT

#include "/lib/Utility.glsl"

layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec4 materialOut;
layout(location = 2) out vec4 normalOut;

vec3 VoxyFaceNormal(uint face) {
	return vec3(
		uint((face >> 1u) == 2u),
		uint((face >> 1u) == 0u),
		uint((face >> 1u) == 1u)
	) * uintBitsToFloat((face << 31u) ^ 0xBF800000u);
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec4 baseColor = parameters.sampledColour * parameters.tinting;
	vec3 geoNormal = VoxyFaceNormal(parameters.face);
	vec2 lightmap = saturate((parameters.lightMap - 0.03125) * 1.06667);

	albedoOut = vec4(baseColor.rgb, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = max(parameters.customId - 10000u, 1u);
	materialOut.zw = uvec2(0u);

	normalOut.xy = OctEncodeSnorm(geoNormal);
	normalOut.zw = normalOut.xy;
}
