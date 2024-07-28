/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_SETTINGS
#define INCLUDE_SETTINGS

#define INFO Alpha // [Alpha Beta Release]
#define AUTHOR HaringPro

//======// Environment //=========================================================================//

const ivec2 skyViewRes = ivec2(255, 192);

const float minCloudTransmittance = 0.05;
const float minCloudAbsorption	  = 0.01;

/* Clouds */
	#define CLOUDS_ENABLED // Enables clouds
	// #define CLOUD_SHADOWS // Enables cloud shadows

	#ifndef CLOUDS_ENABLED
		#undef CLOUD_SHADOWS
	#endif

/* Fog */
	// #define BORDER_FOG // Enables border fog
	#define BORDER_FOG_FALLOFF 12.0 // Falloff of the border fog. [0.0 0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0]

	#define VOLUMETRIC_FOG // Enables volumetric fog
	#define VOLUMETRIC_FOG_SAMPLES 18 // Sample count of volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 24 28 30 40 50 70 100 150 200 300 500]
	#define FOG_QUALITY 1 // [0 1]

	// #define COLORED_VOLUMETRIC_FOG // Enables volumetric fog stained glass tint
	#define TIME_FADE // Reduces fog density at noon

	#define FOG_MIE_DENSITY 0.0044 // Mie scattering density
	#define FOG_RAYLEIGH_DENSITY 0.0001 // Rayleigh scattering density
	#define FOG_MIE_DENSITY_RAIN_MULTIPLIER 5.0 // Mie scattering density multiplier when raining
	#define SEA_LEVEL 63.0 // Sea level. [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0 121.0 122.0 123.0 124.0 125.0 126.0 127.0 128.0 129.0 130.0 131.0 132.0 133.0 134.0 135.0 136.0 137.0 138.0 139.0 140.0 141.0 142.0 143.0 144.0 145.0 146.0 147.0 148.0 149.0 150.0 151.0 152.0 153.0 154.0 155.0 156.0 157.0 158.0 159.0 160.0 161.0 162.0 163.0 164.0 165.0 166.0 167.0 168.0 169.0 170.0 171.0 172.0 173.0 174.0 175.0 176.0 177.0 178.0 179.0 180.0 181.0 182.0 183.0 184.0 185.0 186.0 187.0 188.0 189.0 190.0 191.0 192.0 193.0 194.0 195.0 196.0 197.0 198.0 199.0 200.0 201.0 202.0 203.0 204.0 205.0 206.0 207.0 208.0 209.0 210.0 211.0 212.0 213.0 214.0 215.0 216.0 217.0 218.0 219.0 220.0 221.0 222.0 223.0 224.0 225.0 226.0 227.0 228.0 229.0 230.0 231.0 232.0 233.0 234.0 235.0 236.0 237.0 238.0 239.0 240.0 241.0 242.0 243.0 244.0 245.0 246.0 247.0 248.0 249.0 250.0 251.0 252.0 253.0 254.0 255.0]

	#define UW_VOLUMETRIC_FOG // Enables underwater volumetric fog
	#define UW_VOLUMETRIC_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]
	#define UW_VOLUMETRIC_FOG_SAMPLES 20 // Sample count of underwater volumetric fog. [2 4 6 8 9 10 12 14 15 16 18 20 22 24 26 28 30 40 50 70 100 150 200 300 500]

/* Transparent */
	#define WATER_PARALLAX // Enables water parallax
	#define WATER_CAUSTICS // Enables water caustics

	#define WATER_REFRACT_IOR 1.33 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.33 1.4 1.5 1.6]
	#define WATER_WAVE_HEIGHT 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
	#define WATER_WAVE_SPEED 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.5 6.0 6.5 7.0 7.5 8.0 9.5 10.0]
	#define WATER_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

	#define WATER_ABSORPTION_R 0.3  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_G 0.1  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_B 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

	// #define TRANSLUCENT_LIGHTING // Enables translucent lighting
	#define TRANSLUCENT_LIGHTING_BLEND_FACTOR 0.25 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define GLASS_REFRACT_IOR 1.5 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]

/* Weather */
	#define RAIN_VISIBILITY	0.25 // Visibility of the rain. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//======// Lighting //============================================================================//

/* Lighting */
	#define HANDHELD_LIGHTING // Enables handheld lighting
	#define HELD_LIGHT_BRIGHTNESS 0.1 // Brightness of the handheld light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]
	#define BLOCKLIGHT_TEMPERATURE 3000 // [1000 1500 2000 2300 2500 3000 3400 3500 4000 4500 5000 5500 6000]

/* Lighting brightness */
	#define MINIMUM_AMBIENT_BRIGHTNESS 0.00005 // Minimum brightness of the ambient light. [0.0 0.00001 0.00002 0.00003 0.00005 0.00007 0.0001 0.0002 0.0003 0.0004 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0015 0.002 0.0025 0.003 0.004 0.005 0.006 0.007 0.01 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define NIGHT_BRIGHTNESS 0.0005 // Brightness of the night. [0.0 0.00005 0.00007 0.0001 0.0002 0.0003 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0015 0.002 0.0025 0.003 0.004 0.005 0.006 0.007 0.01 0.05 1.0]

/* Global illumination */
	// #define SSPT_ENABLED // Enables screen-space path tracing
	#define SVGF_ENABLED // Enables spatiotemporal variance-guided filtering

/* Ambient occlusion */
	#define AO_ENABLED 1 // Enables ambient occlusion. [0 1 2]

/* Shadows */
	#define COLORED_SHADOWS // Enables colored shadows

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

/* Parallax */
	#define PARALLAX // Enables parallax mapping
	#define PARALLAX_DEPTH_WRITE // Enables parallax depth write

	#define PARALLAX_SHADOW // Enables parallax shadow
	// #define PARALLAX_BASED_NORMAL // Enables parallax based normal

	#define PARALLAX_SAMPLES 60 // Number of parallax samples. [10 20 30 40 50 60 70 80 90 100 120 150 200 250 300 400 500 600 700 1000]
	#define PARALLAX_DEPTH 0.2 // Parallax depth. [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0][0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0 7.0 10.0]
	#define PARALLAX_REFINEMENT // Enables parallax refinement
	#define PARALLAX_REFINEMENT_STEPS 8 // Number of parallax refinement steps. [4 8 12 16 20 24 28 32 36 40 44 48 52 56 60 64 68 72 76 80 84 88 92 96 100] [2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 24]

	#if !defined NORMAL_MAPPING
		#undef PARALLAX
	#endif

/* Reflections */
	#define ROUGH_REFLECTIONS // Enables rough reflections
	#define ROUGH_REFLECTIONS_THRESHOLD 0.01 // Threshold for rough reflections. [0.0001 0.0002 0.0005 0.0007 0.001 0.002 0.005 0.007 0.01 0.02 0.05 0.07 0.1 0.2 0.5]

	#define REFLECTION_FILTER // Enables reflection filter

	#ifdef REFLECTION_FILTER
	#endif

	#define SPECULAR_HIGHLIGHT_BRIGHTNESS 0.5 // Brightness of the specular high light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]

/* Emissive */
	#define EMISSIVE_MODE 0 // [0 1 2]
	#define EMISSIVE_BRIGHTNESS 1.0 // Brightness of emissive. [0.0 0.1 0.2 0.3 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 18.5 19.0 19.5 20.0 20.5 21.0 21.5 22.0 22.5 23.0 23.5 24.0 24.5 25.0]
	#define EMISSIVE_CURVE 2.2 // Emissive curve. [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.2 5.4 5.6 5.8 6.0 6.2 6.4 6.6 6.8 7.0 7.2 7.4 7.6 7.8 8.0 8.2 8.4 8.6 8.8 9.0 9.2 9.4 9.6 9.8 10.0] [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0]

/* Subsurface Scattering */
	#define SUBSERFACE_SCATTERING_MODE 0 // [0 1 2]
	#define SUBSERFACE_SCATTERING_STRENTGH 1.0 // Strength of subsurface scattering. [0.0 0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]
	#define SUBSERFACE_SCATTERING_BRIGHTNESS 4.0 // Brightness of subsurface scattering. [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 18.5 19.0 19.5 20.0 20.5 21.0 21.5 22.0 22.5 23.0 23.5 24.0 24.5 25.0]

//======// Post-Processing //=====================================================================//

/* TAA */
	#define TAA_ENABLED // Enables temporal Anti-Aliasing
	#define TAA_CLOSEST_FRAGMNET // Caclulates the closest fragment for TAA. Improves ghosting in the motion objects
	#define TAA_BLEND_WEIGHT 0.97 // Blend weight of the TAA. [0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 0.995 0.999]

	#define TAA_VARIANCE_CLIPPING // Enables TAA variance clipping
	#define TAA_AGGRESSION 1.3 // Strictness of TAA variance clipping. [1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0 2.05 2.1 2.15 2.2 2.25 2.3 2.35 2.4 2.45 2.5 2.55 2.6 2.65 2.7 2.75 2.8 2.85 2.9 2.95 3.0]

	// #define TAA_SHARPEN // Sharpens the image when applying TAA
	#define TAA_SHARPNESS 0.7 // Sharpness of the TAA sharpening. [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Motion Blur */
	#define MOTION_BLUR // Enables motion blur
	#define MOTION_BLUR_SAMPLES 6 // [2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24]
	#define MOTION_BLUR_STRENGTH 0.6 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.5 1.7 2.0 2.5 3.0 3.5 4.0 4.5 5.0 7.0 10.0 12.0 14.0 16.0 18.0 20.0]

/* Bloom */
	#define BLOOM_ENABLED // Enables bloom
	#define BLOOMY_FOG // Enables bloomy fog

/* Exposure */
	#define AUTO_EXPOSURE // Enables auto exposure
	#define AUTO_EXPOSURE_LOD 6 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16]

	#define ISO 100.0 // ISO value. [100.0 200.0 320.0 400.0 500.0 640.0 800.0 1000.0 1250.0 1600.0 2000.0 2500.0 3200.0 4000.0 5000.0 6400.0 8000.0 10000.0 12800.0 16000.0 20000.0 25600.0 32000.0 40000.0 51200.0 64000.0 80000.0]
	#define AUTO_EV_BIAS 0.0 // [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define EXPOSURE_SPEED_DOWN 1.6 // Bright to dim speed. [0.5 0.6 0.7 0.8 0.9 1.0 1.6 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 40.0 50.0]
	#define EXPOSURE_SPEED_UP 3.0 // Dim to bright speed. [0.5 0.6 0.7 0.8 0.9 1.0 1.6 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 40.0 50.0]
	#define MANUAL_EV 12.0 // [0.1 0.3 0.5 1.0 1.5 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 14.0 16.0 18.0 20.0 25.0 30.0 40.0 50.0]

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
	// #define DEBUG_BLOOM_TILES
	// #define DEBUG_GI
	// #define DEBUG_SKY_COLOR
	// #define DEBUG_RESHADING

#endif