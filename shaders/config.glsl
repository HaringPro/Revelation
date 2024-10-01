/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------

	- Pipeline Configuration -

	const int 	colortex0Format 			= R11F_G11F_B10F;
	const int 	colortex1Format 			= RGBA16F;
	const int 	colortex2Format 			= RGBA16F;
	const int 	colortex3Format 			= RGBA16F;
	const int 	colortex4Format 			= R11F_G11F_B10F;
	const int 	colortex5Format 			= R11F_G11F_B10F;
	const int 	colortex6Format 			= RGBA8;
	const int 	colortex7Format 			= RGBA16;
	const int 	colortex8Format 			= RGB16;
	const int 	colortex10Format 			= RGBA8;
	const int 	colortex11Format 			= R11F_G11F_B10F;
	const int 	colortex12Format 			= RGB8;
	const int 	colortex13Format 			= RGBA16F;
	const int 	colortex14Format 			= RGB16;
	const int 	colortex15Format 			= RGB16;

	const bool	colortex0Clear				= false;
	const bool 	colortex1Clear				= false;
	const bool	colortex2Clear				= false;
	const bool	colortex3Clear				= false;
	const bool	colortex4Clear				= false;
	const bool  colortex5Clear				= false;
	const bool  colortex6Clear				= true;
	const bool	colortex7Clear				= false;
	const bool	colortex8Clear				= false;
	const bool 	colortex10Clear				= false;
	const bool 	colortex11Clear				= false;
	const bool 	colortex12Clear				= false;
	const bool 	colortex13Clear				= false;
	const bool 	colortex14Clear				= false;
	const bool 	colortex15Clear				= false;

	const float shadowIntervalSize 			= 2.0;
	const float ambientOcclusionLevel 		= 1.0;
	const float	sunPathRotation				= -35.0; // [-90.0 -89.0 -88.0 -87.0 -86.0 -85.0 -84.0 -83.0 -82.0 -81.0 -80.0 -79.0 -78.0 -77.0 -76.0 -75.0 -74.0 -73.0 -72.0 -71.0 -70.0 -69.0 -68.0 -67.0 -66.0 -65.0 -64.0 -63.0 -62.0 -61.0 -60.0 -59.0 -58.0 -57.0 -56.0 -55.0 -54.0 -53.0 -52.0 -51.0 -50.0 -49.0 -48.0 -47.0 -46.0 -45.0 -44.0 -43.0 -42.0 -41.0 -40.0 -39.0 -38.0 -37.0 -36.0 -35.0 -34.0 -33.0 -32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0]
	const float eyeBrightnessHalflife 		= 10.0;

	const float wetnessHalflife				= 180.0;
	const float drynessHalflife				= 60.0;

	const bool 	shadowHardwareFiltering1 	= true;
*/

#if defined CLOUDS && defined CLOUD_CBR_ENABLED
/*
	const int 	colortex9Format 			= RGBA16F;
	const bool	colortex9Clear				= false;
*/
#endif

/*
--------------------------------------------------------------------------------

	- Buffer Table -

	|   Buffer		|   Format          |   Resolution	|   Usage
	|———————————————|———————————————————|———————————————|———————————————————————————
	|	colortex0	|   r11f_g11f_b10f  |	Full res  	|	Scene data -> Motion blur output
	|	colortex1	|   rgba16f		    |	Full res  	|	Scene history
	|	colortex2	|   rgba16f         |	Full res  	|	Specular reflections, lighting of glass -> Motion vector
	|	colortex3	|   rgba16f         |	Full res  	|	Current indirect light -> Lighting data history
	|	colortex4	|   r11f_g11f_b10f  |	Full res  	|	Reprojected scene history -> Bloom tiles
	|	colortex5	|   r11f_g11f_b10f  |	256, 384   	|	Sky-View LUT, light colors, exposure
	|	colortex6	|   rgba8           |	Full res  	|	Solid albedo, rain alpha
	|	colortex7	|   rgba16          |	Full res  	|	Gbuffer data 0 -> Bloomy fog transmittance
	|	colortex8	|   rgb16           |	Full res  	|	Gbuffer data 1 -> Final output
	|	colortex9	|   rgba16f     	|	Full res	|	Cloud history
	|	colortex10	|   rgba8           |	256, 384   	|	Transmittance-View LUT, cloud shadow map
	|	colortex11	|   r11f_g11f_b10f  |	Half res  	|	Volumetric fog scattering
	|	colortex12	|   rgb8            |	Half res  	|	Volumetric fog transmittance
	|	colortex13	|   rgba16f         |	Full res	|	Cloud data -> Indirect light history, frame index
	|	colortex14	|   rgb16           |	Full res	|	Variance history, inverse depth history
	|	colortex15	|   rgb16           |	Double res	|	FSR EASU output

--------------------------------------------------------------------------------
*/