#define readDepth(texel) 			texelFetch(depthtex0, texel, 0).x
#define readDepthSolid(texel) 		texelFetch(depthtex1, texel, 0).x

#define readDepthFRD(texel) 		(1.0 - texelFetch(colortex2, texel, 0).x)

#define readSceneColor(texel) 		texelFetch(colortex0, texel, 0).rgb

#define readAlbedo(texel) 			texelFetch(colortex6, texel, 0).rgb
#define readGbufferData0(texel) 	texelFetch(colortex7, texel, 0)
#define readGbufferData1(texel) 	texelFetch(colortex8, texel, 0)

#if defined DISTANT_HORIZONS
	#define readDepthDH(texel) 		texelFetch(dhDepthTex0, texel, 0).x
	#define readDepthDHSolid(texel) texelFetch(dhDepthTex1, texel, 0).x
#endif

//================================================================================================//

float FetchDepthFix(in ivec2 texel) {
	float depth = readDepth(texel);
	return depth + 0.38 * step(depth, 0.56);
}

float FetchDepthSoildFix(in ivec2 texel) {
	float depth = readDepthSolid(texel);
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
    return (near * far) / (readDepth(texel) * (near - far) + far);
}

float FetchLinearDepthSolid(in ivec2 texel) {
    return (near * far) / (readDepthSolid(texel) * (near - far) + far);
}
