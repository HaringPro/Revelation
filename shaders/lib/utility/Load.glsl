
#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#define loadDepth1(texel) 			texelFetch(depthtex1, texel, 0).x
#define loadDepth2(texel) 			texelFetch(depthtex2, texel, 0).x

#define loadSceneMain(texel) 		texelFetch(colortex0, texel, 0).rgb

#define loadAlbedo(texel) 			texelFetch(colortex6, texel, 0)
#define loadMaterialPack(texel) 	texelFetch(colortex7, texel, 0)
#define loadNormalPack(texel) 		texelFetch(colortex8, texel, 0)

#define loadParallaxOffset(texel) 	texelFetch(colortex12, texel, 0).x

#define cloudReconstructTex         colortex9
#define cloudReconstructImg         colorimg9

#if defined LOD_MOD
	#define loadDepth0Lod(texel) 	texelFetch(lodDepthTex0, texel, 0).x
	#define loadDepth1Lod(texel)	texelFetch(lodDepthTex1, texel, 0).x
#endif
