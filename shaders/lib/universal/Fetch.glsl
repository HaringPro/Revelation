
float FetchDepthFix(in ivec2 texel) {
	float depth = readDepth0(texel);
	return depth + 0.38 * step(depth, 0.56);
}

float FetchDepthSoildFix(in ivec2 texel) {
	float depth = readDepth1(texel);
	return depth + 0.38 * step(depth, 0.56);
}

vec3 FetchFlatNormal(in vec4 data) {
	return decodeUnitVector(unpackUnorm2x8(data.z));
}

vec3 FetchWorldNormal(in vec4 data) {
	#if defined NORMAL_MAPPING
		return decodeUnitVector(unpackUnorm2x8(data.w));
	#else
		return decodeUnitVector(unpackUnorm2x8(data.z));
	#endif
}

float FetchLinearDepth(in ivec2 texel) {
    return (near * far) / (readDepth0(texel) * (near - far) + far);
}

float FetchLinearDepthSolid(in ivec2 texel) {
    return (near * far) / (readDepth1(texel) * (near - far) + far);
}
