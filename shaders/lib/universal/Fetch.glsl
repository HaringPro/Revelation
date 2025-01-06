
float FetchDepthFix(in ivec2 texel) {
	float depth = loadDepth0(texel);
	return depth + 0.38 * step(depth, 0.56);
}

float FetchDepthSoildFix(in ivec2 texel) {
	float depth = loadDepth1(texel);
	return depth + 0.38 * step(depth, 0.56);
}

vec3 FetchFlatNormal(in uvec4 data) {
	return decodeUnitVector(Unpack2x8U(data.z));
}

vec3 FetchWorldNormal(in uvec4 data) {
	#if defined NORMAL_MAPPING
		return decodeUnitVector(Unpack2x8U(data.w));
	#else
		return decodeUnitVector(Unpack2x8U(data.z));
	#endif
}

float FetchLinearDepth(in ivec2 texel) {
    return ScreenToViewDepth(loadDepth0(texel));
}

float FetchLinearDepthSolid(in ivec2 texel) {
    return ScreenToViewDepth(loadDepth1(texel));
}
