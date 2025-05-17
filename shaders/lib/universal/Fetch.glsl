
float FetchDepthFix(in ivec2 texel) {
	float depth = loadDepth0(texel);
	return depth + 0.38 * step(depth, 0.56);
}

float FetchDepthSoildFix(in ivec2 texel) {
	float depth = loadDepth1(texel);
	return depth + 0.38 * step(depth, 0.56);
}

vec3 FetchFlatNormal(in uvec4 data) {
	return OctDecodeUnorm(Unpack2x8U(data.z));
}

vec3 FetchWorldNormal(in uvec4 data) {
	#if defined NORMAL_MAPPING
		return OctDecodeUnorm(Unpack2x8U(data.w));
	#else
		return OctDecodeUnorm(Unpack2x8U(data.z));
	#endif
}

#if defined DISTANT_HORIZONS
float FetchLinearDepth(in ivec2 texel) {
	float depth = loadDepth0(texel);
	float linearDepth = ScreenToViewDepth(depth);
	if (depth > 0.999999) linearDepth = ScreenToViewDepthDH(loadDepth0DH(texel));
    return linearDepth;
}
float FetchLinearDepthSolid(in ivec2 texel) {
	float depth = loadDepth1(texel);
	float linearDepth = ScreenToViewDepth(depth);
	if (depth > 0.999999) linearDepth = ScreenToViewDepthDH(loadDepth1DH(texel));
    return linearDepth;
}
#else
float FetchLinearDepth(in ivec2 texel) {
    return ScreenToViewDepth(loadDepth0(texel));
}
float FetchLinearDepthSolid(in ivec2 texel) {
    return ScreenToViewDepth(loadDepth1(texel));
}
#endif
