
/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

/*
	Pipeline configuration

	const int 	colortex0Format 			= R11F_G11F_B10F;	// Scene data
	const int 	colortex2Format 			= RGBA16F;			// Temp data
	const int 	colortex3Format 			= RGBA16;			// Gbuffer data 0
	const int 	colortex4Format 			= RGBA16;			// Gbuffer data 1
	const int 	colortex5Format 			= R11F_G11F_B10F;	// Sky-View LUT, light colors
	const int 	colortex6Format 			= RGB8;				// Albedo
	const int 	colortex7Format 			= R11F_G11F_B10F;	// Scene history
	const int 	colortex10Format 			= R11F_G11F_B10F;	// Transmittance-View LUT, cloud shadow map

	const bool	colortex0Clear				= false;
	const bool	colortex2Clear				= true;
	const bool	colortex3Clear				= true;
	const bool	colortex4Clear				= false;
	const bool  colortex5Clear				= false;
	const bool  colortex6Clear				= false;
	const bool	colortex7Clear				= false;
	const bool 	colortex10Clear				= true;


	const float shadowIntervalSize 			= 2.0;
	const float ambientOcclusionLevel 		= 1.0;
	const float	sunPathRotation				= -35.0; // [-90.0 -89.0 -88.0 -87.0 -86.0 -85.0 -84.0 -83.0 -82.0 -81.0 -80.0 -79.0 -78.0 -77.0 -76.0 -75.0 -74.0 -73.0 -72.0 -71.0 -70.0 -69.0 -68.0 -67.0 -66.0 -65.0 -64.0 -63.0 -62.0 -61.0 -60.0 -59.0 -58.0 -57.0 -56.0 -55.0 -54.0 -53.0 -52.0 -51.0 -50.0 -49.0 -48.0 -47.0 -46.0 -45.0 -44.0 -43.0 -42.0 -41.0 -40.0 -39.0 -38.0 -37.0 -36.0 -35.0 -34.0 -33.0 -32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0]
	const float eyeBrightnessHalflife 		= 10.0;

	const float wetnessHalflife				= 180.0;
	const float drynessHalflife				= 60.0;

    const float shadowDistanceRenderMul     = 1.0; // [-1.0 1.0]

	const bool 	shadowHardwareFiltering1 	= true;

    const int   noiseTextureResolution      = 256;
*/
