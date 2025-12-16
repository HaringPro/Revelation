#if !defined INCLUDE_CLOUDS_COMMON
#define INCLUDE_CLOUDS_COMMON

/*
--------------------------------------------------------------------------------

	References:
		[Schneider, 2015] Andrew Schneider. “The Real-Time Volumetric Cloudscapes Of Horizon: Zero Dawn”. SIGGRAPH 2015.
			https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn
		[Schneider, 2016] Andrew Schneider. "GPU Pro 7: Real Time Volumetric Cloudscapes". p.p. (97-128) CRC Press, 2016.
			https://www.taylorfrancis.com/chapters/edit/10.1201/b21261-11/real-time-volumetric-cloudscapes-andrew-schneider
		[Schneider, 2017] Andrew Schneider. "Nubis: Authoring Realtime Volumetric Cloudscapes with the Decima Engine". SIGGRAPH 2017.
			https://advances.realtimerendering.com/s2017/Nubis%20-%20Authoring%20Realtime%20Volumetric%20Cloudscapes%20with%20the%20Decima%20Engine%20-%20Final.pptx
		[Schneider, 2022] Andrew Schneider. "Nubis, Evolved: Real-Time Volumetric Clouds for Skies, Environments, and VFX". SIGGRAPH 2022.
			https://advances.realtimerendering.com/s2022/SIGGRAPH2022-Advances-NubisEvolved-NoVideos.pdf
		[Schneider, 2023] Andrew Schneider. "Nubis Cubed: Methods (and madness) to model and render immersive real-time voxel-based clouds". SIGGRAPH 2023.
			https://advances.realtimerendering.com/s2023/Nubis%20Cubed%20(Advances%202023).pdf
		[Hillaire, 2016] Sebastien Hillaire. “Physically based Sky, Atmosphere and Cloud Rendering”. SIGGRAPH 2016.
			https://blog.selfshadow.com/publications/s2016-shading-course/
			https://www.ea.com/frostbite/news/physically-based-sky-atmosphere-and-cloud-rendering
        [Högfeldt, 2016] Rurik Högfeldt. "Convincing Cloud Rendering: An Implementation of Real-Time Dynamic Volumetric Clouds in Frostbite". Department of Computer Science and Engineering, Gothenburg, Sweden, 2016.
            https://publications.lib.chalmers.se/records/fulltext/241770/241770.pdf
		[Bauer, 2019] Fabian Bauer. "Creating the Atmospheric World of Red Dead Redemption 2: A Complete and Integrated Solution". SIGGRAPH 2019.
			https://www.advances.realtimerendering.com/s2019/slides_public_release.pptx
        [Wrenninge et al., 2013] Magnus Wrenninge, Chris Kulla, Viktor Lundqvist. “Oz: The Great and Volumetric”. SIGGRAPH 2013 Talks.
            https://dl.acm.org/doi/10.1145/2504459.2504518

--------------------------------------------------------------------------------
*/

//================================================================================================//


/* Universal */
    #define CLOUD_AERIAL_PERSPECTIVE            // Enables aerial perspective for clouds

/* Low-level clouds */
    #define CLOUD_CUMULUS 	                    // Enables cumulus clouds

	#ifndef CLOUD_CUMULUS
		#undef CLOUD_SHADOWS
	#endif

    #define CLOUD_LOW_SAMPLES 		   	40      // Sample count for low clouds ray marching. [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 36 40 44 48 50 52 56 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200 210 220 230 240 250 260 270 280 290 300 310 320 330 340 350 360 370 380 390 400 410 420 430 440 450 460 470 480 490 500]

    #define CLOUD_LOW_SUNLIGHT_SAMPLES 	6       // Sample count for sunlight optical depth calculation. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50]
    #define CLOUD_LOW_SKYLIGHT_SAMPLES 	0       // Sample count for skylight optical depth calculation. [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50]
    #define CLOUD_LOW_WIND_SPEED 		10.0    // Wind speed of low clouds. [5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0]

    #define CLOUD_CU_ALTITUDE 		   	1000.0  // Altitude of cumulus clouds. [400.0 500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 75000.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_THICKNESS 		    1500.0  // Thickness of cumulus clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_COVERAGE           0.5     // Coverage of cumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
    #define CLOUD_CU_DENSITY_B          0.2     // Bottom density of cumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0]
    #define CLOUD_CU_DENSITY_T          2.0     // Top density of cumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0]

/* Mid-level clouds */
    #define CLOUD_MID_ALTITUDE 			4000.0  // Altitude of mid clouds.  [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_MID_THICKNESS 		2000.0  // Thickness of mid clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_MID_SUNLIGHT_SAMPLES 	4       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
    #define CLOUD_MID_WIND_SPEED 		20.0    // Wind speed of mid clouds. [5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0]

//  #define CLOUD_ALTOSTRATUS                   // Enables altostratus clouds
    #define CLOUD_AS_COVERAGE           0.5     // Coverage of altostratus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* High-level clouds */
    #define CLOUD_HIGH_ALTITUDE 		6000.0  // Altitude of high clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_HIGH_THICKNESS 		1000.0  // Thickness of high clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_HIGH_SUNLIGHT_SAMPLES 3       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
    #define CLOUD_HIGH_WIND_SPEED 		30.0    // Wind speed of high clouds. [5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0]

    #define CLOUD_CIRRUS 	                    // Enables cirrus clouds
    #define CLOUD_CI_COVERAGE           0.5     // Coverage of cirrus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

    #define CLOUD_CIRROCUMULUS                  // Enables cirrocumulus clouds
    #define CLOUD_CC_COVERAGE           0.5     // Coverage of cirrocumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Cloud shadows */
    #define CLOUD_SHADOW_DISTANCE 		2048.0  // Render distance of cloud shadows. [256.0 512.0 768.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0]
    #define CLOUD_SHADOW_SAMPLES 	    16      // Sample count for cloud shadows. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 22 24 26 28 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 130 140 150 160 170 180 190 200 210 220 230 240 250 260 270 280 290 300 310 320 330 340 350 360 370 380 390 400 410 420 430 440 450 460 470 480 490 500]
    #define CLOUD_SHADOW_STRENGTH 	    0.9     // Strength of cloud shadows. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]


//================================================================================================//

const uint  cloudMsCount 			= 4;

// Must be a <= b to keep energy conservation
const float cloudMsFalloffA 	    = 0.5;
const float cloudMsFalloffB 	    = 0.5;
const float cloudMsFalloffC 	    = 0.5;

const float cloudMapExtend 		    = 128e3; // m

const float cloudForwardG 		    = 0.65;
const float cloudBackwardG 		    = -0.3;
const float cloudLobeMixer          = 0.25;
const float cloudSilverG 		    = 0.95;
const float cloudSilverI 	        = 0.20;

const float cumulusThickness 		= CLOUD_CU_THICKNESS;
const float cumulusBottomAltitude 	= CLOUD_CU_ALTITUDE;

const float cumulusTopAltitude 		= cumulusBottomAltitude + cumulusThickness;
const float cumulusTopOffset        = cumulusThickness * 0.25;

const float cumulusBottomRadius     = planetRadius + cumulusBottomAltitude;
const float cumulusTopRadius        = planetRadius + cumulusTopAltitude;

const float cloudMidThickness       = CLOUD_MID_THICKNESS;
const float cloudHighThickness      = CLOUD_HIGH_THICKNESS;

const float cloudMidRadius          = planetRadius + CLOUD_MID_ALTITUDE;
const float cloudHighRadius         = planetRadius + CLOUD_HIGH_ALTITUDE;

const float cumulusAlbedo 		    = 0.94;
const float stratusAlbedo 		    = 0.88;
const float cirrusAlbedo 		    = 0.85;

const float cumulusScattering 		= 0.05;
const float stratusScattering 		= 0.04;
const float cirrusScattering 		= 0.01;

const float cumulusExtinction 		= cumulusScattering / cumulusAlbedo;
const float stratusExtinction 		= stratusScattering / stratusAlbedo;
const float cirrusExtinction 		= cirrusScattering / cirrusAlbedo;

const float cloudEpsilon            = 0.001;
const float cloudMinTransmittance   = 0.05;

//================================================================================================//

// From [Schneider, 2015]
float remap(float value, float orignalMin, float orignalMax, float newMin, float newMax) {
    return newMin + saturate((value - orignalMin) / (orignalMax - orignalMin)) * (newMax - newMin);
}

#endif