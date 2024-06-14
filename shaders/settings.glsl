/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_SETTINGS
#define INCLUDE_SETTINGS

//======// Atmospherics //========================================================================//

const ivec2 skyCaptureRes = ivec2(255, 192);

//======// Lighting //============================================================================//

/* Lighting */
	#define HANDHELD_LIGHTING // Enables handheld lighting
	#define HELDL_IGHT_BRIGHTNESS 0.1 // Brightness of the handheld light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]
	#define BLOCKLIGHT_TEMPERATURE 3000 // [1000 1500 2000 2300 2500 3000 3400 3500 4000 4500 5000 5500 6000]

/* Lighting brightness */
	#define NIGHT_BRIGHTNESS 0.0005 // Brightness of the night. [0.0 0.00005 0.00007 0.0001 0.0002 0.0003 0.0005 0.0006 0.0007 0.0008 0.0009 0.001 0.0015 0.002 0.0025 0.003 0.004 0.005 0.006 0.007 0.01 0.05 1.0]

/* Ambient Occlusion */
	#define AO_ENABLED 1 // Enables ambient occlusion. [0 1 2]

/* Shadows */
	#define COLORED_SHADOWS // Enables colored shadows

	#define SCREEN_SPACE_SHADOWS // Enables screen space shadows

	// #define SHADOW_BACKFACE_CULLING // Enables backface culling for shadows

//======// World //===============================================================================//

/* Water */
	#define WATER_PARALLAX // Enables water parallax
	#define WATER_WAVE_HEIGHT 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
	#define WATER_WAVE_SPEED 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.5 6.0 6.5 7.0 7.5 8.0 9.5 10.0]
	#define WATER_REFRACT_IOR 1.33 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.33 1.4 1.5 1.6]
	#define WATER_CAUSTICS // Enables water caustics
	#define WATER_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.7 2.0 2.5 3.0 4.0 5.0 7.0 10.0]

	#define WATER_ABSORPTION_R 0.3  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_G 0.1  // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
	#define WATER_ABSORPTION_B 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]


	#define GLASS_REFRACT_IOR 1.5 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]

/* Fog */
	#define BORDER_FOG // Enables border fog
	#define BORDER_FOG_FALLOFF 12.0 // Falloff of the border fog. [0.0 0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0]

/* Surface */
	#define TEXTURE_FORMAT 0 // [0 1 2]

	#define SPECULAR_HIGHLIGHT_BRIGHTNESS 0.6 // Brightness of the specular high light. [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 2.0 2.5 3.0 4.0 5.0 7.0 10.0 15.0]

	#define SUBSERFACE_SCATTERING_MODE 0 // [0 1 2]
	#define SUBSERFACE_SCATTERING_STRENTGH 1.0 // Brightness of subsurface scattering. [0.0 0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 7.0 10.0 15.0]

//======// Post-Processing //=====================================================================//

/* TAA */
	#define TAA_ENABLED // Temporal Anti-Aliasing
	// #define TAA_SHARPEN // Sharpens the image when applying TAA
	#define TAA_SHARPNESS 0.7 // Sharpness of the TAA sharpening. [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Exposure */
	#define AUTO_EXPOSURE // Enables auto exposure
	#define AUTO_EXPOSURE_LOD 6 // [1 2 3 4 5 6 7 8 9 10 11 12 14 16]

	#define EXPOSURE_SPEED 1.0 // Speed of the exposure. [0.1 0.2 0.3 0.5 0.7 1.0 1.3 1.6 2.0 2.5 3.0 5.0 7.0 10.0]
	#define AUTO_EXPOSURE_BIAS 0.0 // [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define MANUAL_EXPOSURE_VALUE 12.0 // [0.1 0.3 0.5 1.0 1.5 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 14.0 16.0 18.0 20.0 25.0 30.0 40.0 50.0]

/* Bloom */
	#define BLOOM_ENABLED // Enables bloom
	#define BLOOMY_FOG // Enables bloomy fog

/* CAS */
	#define CAS_ENABLED // Sharpens the final image (contrast-adaptive sharpening)
	#define CAS_STRENGTH 0.3 // Strength of the CAS. [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//======// Debug //===============================================================================//

// #define WHITE_WORLD

#endif