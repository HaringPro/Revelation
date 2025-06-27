/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_SETTINGS
#define INCLUDE_SETTINGS

#define INFO   Alpha // Development stage of the shaderpack. [Alpha Beta Release]
#define AUTHOR HaringPro // Copyright holder of the shaderpack. [HaringPro]

const int shadowMapResolution = 2048;  // [1024 2048 4096 8192 16384 32768]
const float	shadowDistance 	  = 192.0; // [64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0 768.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0]

//======// Environment //=========================================================================//

const ivec2 skyViewRes 			  = ivec2(256, 192);

// TODO: Physical parameters
const float skyIntensity 		  = 16.0;
const float sunIntensity 		  = 32.0;

/* Aurora */
	// #define AURORA // Enables aurora
	#define AURORA_STRENGTH 0.2 // Strength of the aurora. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0]

/* Clouds */
	#define CLOUDS // Enables clouds
	#define CLOUD_SHADOWS // Enables cloud shadows

	#ifndef CLOUDS
		#undef CLOUD_SHADOWS
	#endif

	#define CLOUD_CBR_ENABLED // Enables cloud checkerboard rendering
	#define CLOUD_CBR_SCALE 2 // Upscaling factor for cloud checkerboard rendering. [2 3 4]
	#define CLOUD_MAX_ACCUM_FRAMES 48 // Maximum number of accumulated frames for cloud temporal upscaling. [16 20 24 28 32 36 40 44 48 52 56 60 64 68 72 76 80 84 88 92 96 100 104 108 112 116 120 124 128 132 136 140 144 148 152 156 160 164 168 172 176 180 184 188 192 196 200 204 208 212 216 220 224 228 232 236 240 244 248 252]
	#define CLOUD_VARIANCE_CLIP // Enables variance clipping for cloud temporal upscaling

	const int cloudRenderArea = CLOUD_CBR_SCALE * CLOUD_CBR_SCALE;

/* Fog */
	// #define BORDER_FOG // Enables border fog
	#define BORDER_FOG_FALLOFF 12.0 // Falloff of the border fog. [0.0 0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0]

	#define PER_BIOME_FOG // Enables per-biome fog

	#define LAVA_FOG // Enables lava fog
	#define POWDERED_SNOW_FOG // Enables powdered snow fog
	#define BLINDNESS_DARKNESS_FOG // Enables blindness & darkness fog

	#define VOLUMETRIC_FOG // Enables volumetric fog
	#define VOLUMETRIC_FOG_SAMPLES 16 // Sample count of volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 24 28 30 40 50 70 100 150 200 300 500]
	#define VOLUMETRIC_FOG_QUALITY 0 // [0 1]

	// #define COLORED_VOLUMETRIC_FOG // Enables volumetric fog stained glass tint
	#define VF_CLOUD_SHADOWS // Enables cloud shadows in volumetric fog
	#define VF_TIME_FADE // Adjussts the density of the volumetric fog based on time of day
	#define SEA_LEVEL 63.0 // Sea level. [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0 121.0 122.0 123.0 124.0 125.0 126.0 127.0 128.0 129.0 130.0 131.0 132.0 133.0 134.0 135.0 136.0 137.0 138.0 139.0 140.0 141.0 142.0 143.0 144.0 145.0 146.0 147.0 148.0 149.0 150.0 151.0 152.0 153.0 154.0 155.0 156.0 157.0 158.0 159.0 160.0 161.0 162.0 163.0 164.0 165.0 166.0 167.0 168.0 169.0 170.0 171.0 172.0 173.0 174.0 175.0 176.0 177.0 178.0 179.0 180.0 181.0 182.0 183.0 184.0 185.0 186.0 187.0 188.0 189.0 190.0 191.0 192.0 193.0 194.0 195.0 196.0 197.0 198.0 199.0 200.0 201.0 202.0 203.0 204.0 205.0 206.0 207.0 208.0 209.0 210.0 211.0 212.0 213.0 214.0 215.0 216.0 217.0 218.0 219.0 220.0 221.0 222.0 223.0 224.0 225.0 226.0 227.0 228.0 229.0 230.0 231.0 232.0 233.0 234.0 235.0 236.0 237.0 238.0 239.0 240.0 241.0 242.0 243.0 244.0 245.0 246.0 247.0 248.0 249.0 250.0 251.0 252.0 253.0 254.0 255.0]

	#define VF_MIE_DENSITY 	 	0.0001 // Mie scattering density. 	   [0.00001 0.00002 0.00005 0.00007 0.0001 0.00015 0.0002 0.0004 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0011 0.0012 0.0013 0.0014 0.0015 0.0016 0.0017 0.0018 0.0019 0.002 0.0021 0.0022 0.0023 0.0024 0.0025 0.0027 0.003 0.0035 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.011 0.012 0.013 0.014 0.015 0.016 0.017 0.018 0.019 0.02 0.021 0.022 0.023 0.024 0.025 0.027 0.03 0.035 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define VF_RAYLEIGH_DENSITY 0.0001 // Rayleigh scattering density. [0.00001 0.00002 0.00005 0.00007 0.0001 0.00015 0.0002 0.0004 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0011 0.0012 0.0013 0.0014 0.0015 0.0016 0.0017 0.0018 0.0019 0.002 0.0021 0.0022 0.0023 0.0024 0.0025 0.0027 0.003 0.0035 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.011 0.012 0.013 0.014 0.015 0.016 0.017 0.018 0.019 0.02 0.021 0.022 0.023 0.024 0.025 0.027 0.03 0.035 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define VF_MIE_DENSITY_RAIN_MULT 4.0 // Mie scattering density multiplier when raining. [0.0 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 18.5 19.0 19.5 20.0]

	#define UW_VOLUMETRIC_FOG // Enables underwater volumetric fog
	#define UW_VOLUMETRIC_FOG_DENSITY 1.0 // Density of underwater volumetric fog. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]
	#define UW_VOLUMETRIC_FOG_SAMPLES 16 // Sample count of underwater volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 22 24 26 28 30 40 50 70 100 150 200 300 500]

	#ifdef PER_BIOME_FOG
	#endif
	#ifdef VF_TIME_FADE
	#endif

/* Transparent */
	#define WATER_PARALLAX // Enables water parallax
	#define WATER_CAUSTICS // Enables water caustics
	// #define WATER_CAUSTICS_DISPERSION // Enables water caustics dispersion
	// #define WATER_CAUSTICS_SIMPLE // Much simpler caustics. Someone may like this better

	#define WATER_REFRACT_IOR 1.25 	// [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.15 1.2 1.25 1.3 1.33 1.4 1.5 1.6]
	#define WATER_WAVE_HEIGHT 1.0 	// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
	#define WATER_WAVE_SPEED 1.0 	// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.5 6.0 6.5 7.0 7.5 8.0 9.5 10.0]
	#define WATER_FOG_DENSITY 1.0 	// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

	#define WATER_ABSORPTION_R 0.35 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_G 0.08 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_B 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

	#define GLASS_REFRACT_IOR 1.5 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]

	// #define TRANSLUCENT_REFLECTION_BLEND // Enables translucent reflection blending
	#define TRANSLUCENT_ROUGHNESS 0.005 // Roughness of translucents. [0.0 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

	#ifdef WATER_CAUSTICS_SIMPLE
	#endif
	#ifdef TRANSLUCENT_REFLECTION_BLEND
	#endif

/* Weather */
	#define RAIN_PUDDLES // Enables rain puddles
	#define RAIN_PUDDLE_SCALE 0.01 // Scale of the rain puddles. [0.001 0.002 0.005 0.007 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]
	#define RAIN_PUDDLE_SMOOTHNESS 0.95 // Smoothness of the rain puddles. [0.0 0.1 0.2 0.3 0.4 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]

	#define RAIN_VISIBILITY	0.5 // Visibility of the rain particles. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define RAIN_SCALE_X	3.0 // X-Scale of the rain particles. [0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 20.0 24.0]
	#define RAIN_SCALE_Y	2.0 // Y-Scale of the rain particles. [0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 20.0 24.0]

//======// Lighting //============================================================================//

/* Lighting */
	#define HANDHELD_LIGHTING // Enables handheld lighting
	#define HELD_LIGHT_BRIGHTNESS 0.1 // Brightness of the handheld light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]
	#define BLOCKLIGHT_TEMPERATURE 3000 // Color temperature of the block light. [1000 1500 2000 2300 2500 3000 3400 3500 4000 4500 5000 5500 6000]

/* Lighting Brightness */
	#define MINIMUM_AMBIENT_BRIGHTNESS 0.00002 // Minimum brightness of the ambient light. [0.0 0.00001 0.00002 0.00003 0.00005 0.00007 0.0001 0.0002 0.0003 0.0004 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0015 0.002 0.0025 0.003 0.004 0.005 0.006 0.007 0.01 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define NIGHT_BRIGHTNESS 0.0005 // Brightness of the night. [0.0 0.00005 0.00007 0.0001 0.0002 0.0003 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0015 0.002 0.0025 0.003 0.004 0.005 0.006 0.007 0.01 0.05 1.0]

/* Global Illumination */
	// #define SSPT_ENABLED // Enables screen-space path tracing
	#define SVGF_ENABLED // Enables spatiotemporal variance-guided filtering

	// #define RSM_ENABLED // Enables reflective shadow maps
	#ifdef SSPT_ENABLED
		#undef RSM_ENABLED
	#endif

	#define SSPT_MAX_ACCUM_FRAMES 96.0 // Maximum accumulated frames for SSPT. [20.0 24.0 28.0 32.0 36.0 40.0 48.0 56.0 64.0 72.0 80.0 96.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 448.0 512.0 640.0 768.0 896.0 1024.0]
	#define RSM_MAX_ACCUM_FRAMES  64.0 // Maximum accumulated frames for RSM.  [20.0 24.0 28.0 32.0 36.0 40.0 48.0 56.0 64.0 72.0 80.0 96.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 448.0 512.0 640.0 768.0 896.0 1024.0]

/* Ambient Occlusion */
	#define OFF 0
	#define SSAO 1
	#define GTAO 2
	#define AO_ENABLED SSAO // Enables ambient occlusion. [OFF SSAO GTAO]
	#define AO_MULTI_BOUNCE // Enables ambient occlusion multi-bounce

/* Shadows */
	#define COLORED_SHADOWS // Enables shadow stained glass tint

	#define SCREEN_SPACE_SHADOWS // Enables screen space shadows
	#define SCREEN_SPACE_SHADOWS_SAMPLES 16 // Sample count of screen space shadows. [2 4 6 8 9 10 12 14 15 16 18 20 22 24 26 28 30 40 50 70 100 150 200 300 500]

	// #define SHADOW_BACKFACE_CULLING // Enables backface culling for shadows

//======// Materials //===========================================================================//

	#define TEXTURE_FORMAT 0 // [0 1 2]

	// #define MOD_BLOCK_SUPPORT // Enables mod block support

	#ifdef MOD_BLOCK_SUPPORT
	#endif

	// #define NORMAL_MAPPING // Enables normal mapping
	// #define SPECULAR_MAPPING // Enables specular mapping

	#if !defined MC_NORMAL_MAP
		#undef NORMAL_MAPPING
	#endif

	#ifdef SPECULAR_MAPPING
	#endif

	#define DEFAULT_DIELECTRIC_F0 0.04 // Default dielectric F0. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Auto Generated Normal */
	// #define AUTO_GENERATED_NORMAL // Enables auto generated normal
	#define AGN_STRENGTH 5.0 // Strength of auto generated normal. [0.2 0.5 0.7 1.0 1.5 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0]
	#define AGN_RESOLUTION 32.0 // Resolution of auto generated normal. [4.0 8.0 16.0 32.0 64.0 128.0 256.0 512.0 1024.0]

/* Parallax */
	#define PARALLAX // Enables parallax mapping
	#define PARALLAX_DEPTH_WRITE // Enables parallax depth write

	#define PARALLAX_SHADOW // Enables parallax shadow
	#define PARALLAX_BASED_NORMAL // Enables parallax based normal

	#define PARALLAX_SAMPLES 60 // Sample count of parallax. [10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 130 140 150 160 170 180 190 200 220 240 260 280 300 350 400 450 500 550 600 650 700 750 800 850 900 950 1000]
	#define PARALLAX_DEPTH 0.25 // Parallax depth. [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0][0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0 7.0 10.0]
	#define PARALLAX_REFINEMENT // Enables parallax refinement
	#define PARALLAX_REFINEMENT_STEPS 8 // Sample count of parallax refinement. [4 8 12 16 20 24 28 32 36 40 44 48 52 56 60 64 68 72 76 80 84 88 92 96 100] [2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 24]

/* Reflections */
	#define ROUGH_REFLECTIONS // Enables rough reflections
	#define ROUGH_REFLECTIONS_THRESHOLD 0.005 // Threshold for rough reflections. [0.0001 0.0002 0.0005 0.0007 0.001 0.002 0.005 0.007 0.01 0.02 0.05 0.07 0.1 0.2 0.5]

	#define REFLECTION_FILTER // Enables reflection filter

	#ifdef REFLECTION_FILTER
	#endif

	#define SPECULAR_IMPORTANCE_SAMPLING_BIAS 0.7 // Specular importance sampling bias. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	// #define SPECULAR_HIGHLIGHT_BRIGHTNESS 0.6 // Brightness of the specular high light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]

/* Emissive */
	#define EMISSIVE_MODE 0 // [0 1 2]
	#define EMISSIVE_BRIGHTNESS 0.5 // Brightness of emissive. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 18.5 19.0 19.5 20.0 20.5 21.0 21.5 22.0 22.5 23.0 23.5 24.0 24.5 25.0]
	#define EMISSIVE_CURVE 2.2 // Emissive curve. [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.2 5.4 5.6 5.8 6.0 6.2 6.4 6.6 6.8 7.0 7.2 7.4 7.6 7.8 8.0 8.2 8.4 8.6 8.8 9.0 9.2 9.4 9.6 9.8 10.0] [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

/* Subsurface Scattering */
	#define SUBSURFACE_SCATTERING_MODE 0 // [0 1 2]
	#define SUBSURFACE_SCATTERING_STRENGTH 1.0 // Strength of subsurface scattering. [0.0 0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]
	#define SUBSURFACE_SCATTERING_BRIGHTNESS 2.0 // Brightness of subsurface scattering. [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]


	#if !defined NORMAL_MAPPING
		#undef PARALLAX
		#undef AUTO_GENERATED_NORMAL
	#endif
	#if defined AUTO_GENERATED_NORMAL
		#undef PARALLAX
	#endif

//======// Post-Processing //=====================================================================//

/* Depth of Field */
	// #define DEPTH_OF_FIELD // Enables depth of field
	#define CAMERA_FOCUS_MODE 0 // [0 1]

/* TAA */
	#define TAA_ENABLED // Enables temporal Anti-Aliasing
	#define TAA_CLOSEST_FRAGMENT // Caclulates the closest fragment for TAA. Improves ghosting in the motion objects
	#define TAA_MAX_ACCUM_FRAMES 96.0 // Maximum number of accumulated frames for TAA. [20.0 24.0 28.0 32.0 36.0 40.0 48.0 56.0 64.0 72.0 80.0 96.0 112.0 128.0 144.0 160.0 192.0 224.0 256.0 320.0 384.0 448.0 512.0 640.0 768.0 896.0 1024.0]

	#define TAA_VARIANCE_CLIPPING // Enables TAA variance clipping
	#define TAA_AGGRESSION 1.75 // Strictness of TAA variance clipping. [1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0 2.05 2.1 2.15 2.2 2.25 2.3 2.35 2.4 2.45 2.5 2.55 2.6 2.65 2.7 2.75 2.8 2.85 2.9 2.95 3.0]

	// #define TAA_SHARPEN // Sharpens the image when applying TAA
	#define TAA_SHARPNESS 0.5 // Sharpness of the TAA sharpening. [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Motion Blur */
	#define MOTION_BLUR // Enables motion blur
	#define MOTION_BLUR_SAMPLES 6 // Sample count of motion blur. [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24]
	#define MOTION_BLUR_STRENGTH 0.5 // Strength of the motion blur. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.5 1.7 2.0 2.5 3.0 3.5 4.0 4.5 5.0 7.0 10.0 12.0 14.0 16.0 18.0 20.0]

/* Bloom */
	#define BLOOM_ENABLED // Enables bloom
	#define BLOOMY_FOG // Enables bloomy fog

/* Exposure */
	#define MANUAL 0
	#define AUTO_BASIC 1
	#define AUTO_HISTOGRAM 2

	#define EXPOSURE_MODE AUTO_HISTOGRAM // [MANUAL AUTO_BASIC AUTO_HISTOGRAM]
	#define AUTO_EXPOSURE_LOD 5 // LOD level for auto exposure. [1 2 3 4 5 6 7 8 9 10 11 12 14 16]

	#define ISO 100.0 // Sensitivity of the camera. [100.0 200.0 320.0 400.0 500.0 640.0 800.0 1000.0 1250.0 1600.0 2000.0 2500.0 3200.0 4000.0 5000.0 6400.0 8000.0 10000.0 12800.0 16000.0 20000.0 25600.0 32000.0 40000.0 51200.0 64000.0 80000.0 10. [100.0 200.0 320.0 400.0 500.0 640.0 800.0 1000.0 1250.0 1600.0 2000.0 2500.0 3200.0 4000.0 5000.0 6400.0 8000.0 10000.0 12800.0 16000.0 20000.0 25600.0 32000.0 40000.0 51200.0 64000.0 80000.0]
	#define AUTO_EV_MIN -8.0 // Minimum EV value for auto exposure. [-32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0]
	#define AUTO_EV_MAX  8.0  // Maximum EV value for auto exposure. [-32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0]
	#define AUTO_EV_BIAS 0.0  // EV bias for auto exposure. [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define MANUAL_EV 2.0 // Manual exposure value. [0.1 0.3 0.5 1.0 1.5 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 14.0 16.0 18.0 20.0 25.0 30.0 40.0 50.0]

	#define EXPOSURE_SPEED_UP 2.4 // Dim to bright speed. [0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.6 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 40.0 50.0]
	#define EXPOSURE_SPEED_DOWN 1.2 // Bright to dim speed. [0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.6 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 40.0 50.0]

	#define HISTOGRAM_BIN_COUNT 64 // Number of bins for the histogram. [8 16 32 64 128 256 512 1024]
	#define HISTOGRAM_LOWER_BOUND 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define HISTOGRAM_UPPER_BOUND 0.6 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

/* FidelityFX */
	// #define FSR_ENABLED // Enables AMD FidelityFX Super Resolution
	#define FSR_RCAS_DENOISE // Enables RCAS denoising
	#define FSR_RCAS_LIMIT (0.25 - rcp(16.0))
	#define FSR_RCAS_SHARPNESS 0.5 // Sharpness of the FSR RCAS. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

	#define CAS_ENABLED // Sharpens the final image using AMD FidelityFX CAS (Contrast-Adaptive Sharpening)
	#define CAS_STRENGTH 0.4 // Strength of the CAS. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//======// Debug //===============================================================================//

	// #define WHITE_WORLD
	#define DEBUG_NORMALS 0 // [0 1 2]
	// #define DEBUG_DEPTH 0 // [0 1 2]
	// #define DEBUG_SKYVIEW
	// #define DEBUG_BLOOM_TILES
	// #define DEBUG_GI
	// #define DEBUG_CLOUD_SHADOWS
	// #define DEBUG_SKY_COLOR
	// #define DEBUG_RESHADING

#endif