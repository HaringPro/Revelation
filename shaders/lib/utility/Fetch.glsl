
#define sampleDepth(texel) texelFetch(depthtex0, texel, 0).x
#define sampleDepthSoild(texel) texelFetch(depthtex1, texel, 0).x

#define sampleSceneColor(texel) texelFetch(colortex0, texel, 0).rgb
#define sampleGbufferData0(texel) texelFetch(colortex7, texel, 0)
#define sampleGbufferData1(texel) texelFetch(colortex8, texel, 0)


float GetDepthFix(in ivec2 texel) {
	float depth = texelFetch(depthtex0, texel, 0).x;
	return depth + 0.38 * step(depth, 0.56);
}

float GetDepthSoildFix(in ivec2 texel) {
	float depth = texelFetch(depthtex1, texel, 0).x;
	return depth + 0.38 * step(depth, 0.56);
}

// vec3 GetFlatNormal(in ivec2 texel) {
// 	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex7, texel, 0).z));
// }

// vec3 GetWorldNormal(in ivec2 texel) {
// 	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex7, texel, 0).w));
// }

vec3 GetFlatNormal(in vec4 data) {
	return decodeUnitVector(unpackUnorm2x8(data.z));
}

#if defined MC_NORMAL_MAP
	vec3 GetWorldNormal(in vec4 data) {
		return decodeUnitVector(unpackUnorm2x8(data.w));
	}
#else
	vec3 GetWorldNormal(in vec4 data) {
		return decodeUnitVector(unpackUnorm2x8(data.z));
	}
#endif

float GetLinearDepth(in ivec2 texel) {
    return (near * far) / (sampleDepth(texel) * (near - far) + far);
}

float GetLinearDepthSolid(in ivec2 texel) {
    return (near * far) / (sampleDepthSoild(texel) * (near - far) + far);
}
