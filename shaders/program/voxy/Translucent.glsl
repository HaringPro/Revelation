// Keep Voxy patch path stable: do not emit #extension from shared includes.
#define INCLUDE_UTILITY_COMPAT

#include "/lib/Utility.glsl"
#include "/lib/water/WaterWave.glsl"

layout(location = 0) out uvec4 materialOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 waterOut;

vec3 VoxyFaceNormal(uint face) {
	return vec3(
		uint((face >> 1u) == 2u),
		uint((face >> 1u) == 0u),
		uint((face >> 1u) == 1u)
	) * uintBitsToFloat((face << 31u) ^ 0xBF800000u);
}

vec3 ScreenToViewPos(vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	return projectAndDivide(vxProjInv, ndcPos);
}

vec2 VoxyScreenCoord(vec2 fragCoord) {
	return fragCoord / vec2(textureSize(vxDepthTexOpaque, 0));
}

float BlueNoise(ivec2 texel, int frame) {
	float base = texelFetch(noisetex, texel & 255, 0).a;
	#ifdef TAA_ENABLED
		return fract(base + float(frame) * PHI);
	#else
		return base;
	#endif
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = VoxyScreenCoord(gl_FragCoord.xy);

	vec4 baseColor = parameters.sampledColour * parameters.tinting;
	vec2 lightmap = vec2(0.0, saturate((parameters.lightMap.y - 0.03125) * 1.06667));

	bool waterMask = parameters.customId == 10003u;
	uint materialId = waterMask ? 3u : 2u;

	vec3 geoNormal = VoxyFaceNormal(parameters.face);
	vec2 encodedNormal = OctEncodeSnorm(geoNormal);

	materialOut.x = Pack2x8U(lightmap);
	materialOut.y = materialId;
	materialOut.zw = uvec2(0u);

	normalOut.xy = normalOut.zw = encodedNormal;

	waterOut = vec4(0.0);

	if (waterMask) {
		vec3 viewPos = ScreenToViewPos(vec3(screenCoord, gl_FragCoord.z));
		vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		mat3 tbnMatrix = BuildOrthonormalBasis(geoNormal);

		vec3 minecraftPos = worldPos + cameraPosition;
		#ifdef WATER_PARALLAX
			vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
		#else
			vec3 worldNormal = CalculateWaterNormal(minecraftPos);
		#endif

		worldNormal = tbnMatrix * worldNormal;

		vec2 encodedWaterNormal = OctEncodeSnorm(worldNormal);
		normalOut.zw = encodedWaterNormal;

		float depthBack = texelFetch(vxDepthTexOpaque, texelPos, 0).x;
		vec3 viewPosBack = ScreenToViewPos(vec3(screenCoord, depthBack));
		vec3 worldPosBack = transMAD(gbufferModelViewInverse, viewPosBack);
		float waterDepth = distance(worldPos, worldPosBack);

		waterOut = vec4(waterDepth * rcp255, Pack2x8(encodedWaterNormal), 0.0, 1.0);
	} else {
		materialOut.z = Pack2x8U(baseColor.xy);
		materialOut.w = Pack2x8U(baseColor.zw);
	}
}
