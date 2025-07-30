
#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#define loadDepth1(texel) 			texelFetch(depthtex1, texel, 0).x

#define loadSceneColor(texel) 		texelFetch(colortex0, texel, 0).rgb

#define loadAlbedo(texel) 			texelFetch(colortex6, texel, 0).rgb
#define loadGbufferData0(texel) 	texelFetch(colortex7, texel, 0)
#define loadGbufferData1(texel) 	texelFetch(colortex8, texel, 0)

#if defined DISTANT_HORIZONS
	#define loadDepth0DH(texel) 	texelFetch(dhDepthTex0, texel, 0).x
	#define loadDepth1DH(texel)		texelFetch(dhDepthTex1, texel, 0).x
#endif

#define skyViewTex					colortex5
#define skyViewImg					colorimg5

#define cloudReconstructTex			colortex9
#define cloudReconstructImg			colorimg9

#define cloudShadowTex				colortex10
#define cloudShadowImg				colorimg10