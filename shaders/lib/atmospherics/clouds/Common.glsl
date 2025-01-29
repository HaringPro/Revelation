#if !defined INCLUDE_CLOUDS_COMMON
#define INCLUDE_CLOUDS_COMMON

//================================================================================================//


/* Universal */
    #define CLOUD_AERIAL_PERSPECTIVE            // Enables aerial perspective for clouds
//  #define CLOUD_LOCAL_LIGHTING                // Enables local lighting for clouds

    #define CLOUD_WIND_SPEED 			0.005   // Wind speed of clouds. [0.0 0.0001 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
    #define CLOUD_MS_COUNT              4       // Times of multi-scattering for clouds. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50]
    #define CLOUD_MS_FALLOFF            0.6     // Multi-scattering falloff for clouds. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]// Multi-scattering factor for clouds. [0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Low-cloud family */
    #define CLOUD_CUMULUS 	                    // Enables cumulus clouds
//  #define CLOUD_CU_ADVANCED_POWDER            // Enables advanced powder effect for cumulus clouds

    #define CLOUD_CU_SAMPLES 		   	22      // Sample count for cumulus clouds ray marching. [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 36 40 50 60 100]

    #define CLOUD_CU_SUNLIGHT_SAMPLES 	4       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
    #define CLOUD_CU_SKYLIGHT_SAMPLES 	2       // Sample count for skylight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

    #define CLOUD_CU_ALTITUDE 		   	800.0   // Altitude of cumulus clouds. [400.0 500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 75000.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_THICKNESS 		    2000.0  // Thickness of cumulus clouds. [1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_COVERAGE           0.5     // Coverage of cumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Mid-cloud family */
    #define CLOUD_MID_ALTITUDE 			3500.0  // Altitude of mid clouds.  [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 cumulusMaxAltitude 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_MID_SUNLIGHT_SAMPLES 	3       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

//  #define CLOUD_ALTOSTRATUS                   // Enables altostratus clouds
    #define CLOUD_AS_COVERAGE           0.6     // Coverage of altostratus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* High-cloud family */
    #define CLOUD_HIGH_ALTITUDE 		7500.0  // Altitude of high clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 cumulusMaxAltitude 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_HIGH_SUNLIGHT_SAMPLES 3       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

    #define CLOUD_CIRRUS 	                    // Enables cirrus clouds
    #define CLOUD_CI_COVERAGE           0.65    // Coverage of cirrus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

    #define CLOUD_CIRROCUMULUS                  // Enables cirrocumulus clouds
    #define CLOUD_CC_COVERAGE           0.6     // Coverage of cirrocumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Cloud shadows */
	#if defined DISTANT_HORIZONS
		#define inf float(dhRenderDistance)
	#else
		#define inf far
	#endif
    #define CLOUD_SHADOW_DISTANCE 		512.0     // Render distance of cloud shadows. [inf 32.0 64.0 128.0 256.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0]


//================================================================================================//

const uint  cloudMsCount 			= CLOUD_MS_COUNT;
const float cloudMsFalloff 			= CLOUD_MS_FALLOFF;

const float cumulusMaxAltitude 		= CLOUD_CU_ALTITUDE + CLOUD_CU_THICKNESS;
const float cumulusTopOffset        = 600.0;

const float cumulusExtinction 		= 0.11;
// const float cumulusScattering 	= 0.11;

const float stratusExtinction 		= 0.1;
const float cirrusExtinction 		= 0.08;
// const float cirrusScattering 	= 0.1;

uniform sampler3D depthtex2;    // 3D perlin-worley & worley noise texture
uniform sampler3D colortex15;   // 3D worley noise texture

uniform vec3 cloudWindCu;
uniform vec2 cloudWindAs;
uniform vec2 cloudWindCc;
uniform vec2 cloudWindCi;
uniform vec3 cloudLightVector;

//================================================================================================//

void ToPlanetCurvePos(inout vec3 pos) {
	pos.y += planetRadius;
	pos.y = length(pos); // sqrt(x^2 + y^2 + z^2)
	pos.y -= planetRadius;
}

void FromPlanetCurvePos(inout vec3 pos) {
	pos.y += planetRadius;
	pos.y = sqrt(pos.y * pos.y - pos.x * pos.x - pos.z * pos.z); // sqrt(y^2 - x^2 - z^2)
	pos.y -= planetRadius;
}

// Quadratic polynomial smooth-min function from https://www.iquilezles.org/www/articles/smin/smin.htm
float smin(float a, float b, float k) {
    k *= 4.0;
    float h = max0(k - abs(a - b)) / k;
    return min(a, b) - h * h * k * 0.25;
}

#endif