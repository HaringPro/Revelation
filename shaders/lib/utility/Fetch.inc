
#define sampleDepth(texel) texelFetch(depthtex0, texel, 0).x
#define sampleDepthSoild(texel) texelFetch(depthtex1, texel, 0).x

float CalculateBlocklightFalloff(in float blocklight) {
	blocklight = rcp(sqr(16.0 - 15.0 * blocklight)) + sqr(blocklight) * 0.05;
	return remap(rcp(256.0), 1.0, blocklight);
}

float GetDepthFix(in ivec2 texel) {
	float depth = texelFetch(depthtex0, texel, 0).x;
	return depth + 0.38 * step(depth, 0.56);
}

vec3 GetNormal(in ivec2 texel) {
	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex4, texel, 0).y) * 2.0 - 1.0);
}

vec3 GetFlatNormal(in ivec2 texel) {
	return decodeUnitVector(unpackUnorm2x8(texelFetch(colortex4, texel, 0).x) * 2.0 - 1.0);
}

float GetLinearDepth(in ivec2 texel) {
    return (near * far) / (texelFetch(depthtex0, texel, 0).x * (near - far) + far);
}

float GetLinearDepthSolid(in ivec2 texel) {
    return (near * far) / (texelFetch(depthtex1, texel, 0).x * (near - far) + far);
}
