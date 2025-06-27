
#define atmosCombinedLut 			colortex0

#define starmapNASA 				colortex12

#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#define loadDepth1(texel) 			texelFetch(depthtex1, texel, 0).x

#define loadSceneColor(texel) 		texelFetch(colortex0, texel, 0).rgb

#define loadAlbedo(texel) 			texelFetch(colortex6, texel, 0).rgb
#define loadGbufferData0(texel) 	texelFetch(colortex7, texel, 0)
#define loadGbufferData1(texel) 	texelFetch(colortex8, texel, 0)

#define loadDirectIllum()			texelFetch(colortex4, ivec2(textureSize(colortex4, 0).x - 1, 0), 0).rgb
#define loadSkyIllum()				texelFetch(colortex4, ivec2(textureSize(colortex4, 0).x - 1, 1), 0).rgb

#define loadExposure()				texelFetch(colortex1, ivec2(0), 0).a

#if defined DISTANT_HORIZONS
	#define loadDepth0DH(texel) 	texelFetch(dhDepthTex0, texel, 0).x
	#define loadDepth1DH(texel)		texelFetch(dhDepthTex1, texel, 0).x
#endif
