vec3 FetchBaseColor(ivec2 texel) {
	return sRGBToLinear(loadAlbedo(texel).rgb) * sRGB_2_Rec2020;
}

vec3 FetchGeometryNormal(ivec2 texel) {
	return OctDecodeSnorm(loadNormalPack(texel).xy);
}

vec3 FetchSurfaceNormal(ivec2 texel) {
	return OctDecodeSnorm(loadNormalPack(texel).zw);
}

void FetchNormalData(ivec2 texel, out vec3 geometryNormal, out vec3 surfaceNormal) {
	vec4 pack = loadNormalPack(texel);
	geometryNormal = OctDecodeSnorm(pack.xy);
	surfaceNormal = OctDecodeSnorm(pack.zw);
}

vec4 ExtractSpecularTex(uvec4 pack) {
	return vec4(Unpack2x8U(pack.z), Unpack2x8U(pack.w));
}
