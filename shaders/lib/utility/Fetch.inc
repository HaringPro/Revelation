
#define sampleDepth(texel) texelFetch(depthtex0, texel, 0).x
#define sampleDepthSoild(texel) texelFetch(depthtex1, texel, 0).x

#define sampleSceneColor(texel) texelFetch(colortex0, texel, 0).rgb

float GetDepthFix(in ivec2 texel) {
	float depth = texelFetch(depthtex0, texel, 0).x;
	return depth + 0.38 * step(depth, 0.56);
}

vec3 GetWorldNormal(in ivec2 texel) {
	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex4, texel, 0).y));
}

vec3 GetFlatNormal(in ivec2 texel) {
	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex4, texel, 0).x));
}

float GetLinearDepth(in ivec2 texel) {
    return (near * far) / (texelFetch(depthtex0, texel, 0).x * (near - far) + far);
}

float GetLinearDepthSolid(in ivec2 texel) {
    return (near * far) / (texelFetch(depthtex1, texel, 0).x * (near - far) + far);
}
