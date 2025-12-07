
#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#define loadDepth1(texel) 			texelFetch(depthtex1, texel, 0).x
#define loadDepth2(texel) 			texelFetch(depthtex2, texel, 0).x

#define loadSceneMain(texel) 		texelFetch(colortex0, texel, 0).rgb

#define loadAlbedo(texel) 			texelFetch(colortex6, texel, 0).rgb
#define loadMaterialPack(texel) 	texelFetch(colortex7, texel, 0)
#define loadNormalPack(texel) 		texelFetch(colortex8, texel, 0)

#if defined DISTANT_HORIZONS
	#define loadDepth0Lod(texel) 	texelFetch(dhDepthTex0, texel, 0).x
	#define loadDepth1Lod(texel)	texelFetch(dhDepthTex1, texel, 0).x
#elif defined VOXY
	#define loadDepth0Lod(texel) 	texelFetch(vxDepthTexTrans, texel, 0).x
	#define loadDepth1Lod(texel)	texelFetch(vxDepthTexOpaque, texel, 0).x
#endif

#define skyMapTex					colortex5
#define skyMapImg					colorimg5

#define cloudReconstructTex			colortex9
#define cloudReconstructImg			colorimg9

#define cloudShadowTex				colortex10
#define cloudShadowImg				colorimg10