#if !defined INCLUDE_CLOUDS_COMMON
#define INCLUDE_CLOUDS_COMMON

//================================================================================================//

    #define CLOUD_CUMULUS 	        // Enables cumulus clouds
//  #define CLOUD_STRATOCUMULUS     // Enables stratocumulus clouds
    #define CLOUD_CIRROCUMULUS      // Enables cirrocumulus clouds
    #define CLOUD_CIRRUS 	        // Enables cirrus clouds

    #define CLOUD_AERIAL_PERSPECTIVE       // Enables aerial perspective for clouds

//  #define CLOUD_CUMULUS_ADVANCED_POWDER  // Enables advanced powder effect for cumulus clouds
//  #define CLOUD_LOCAL_LIGHTING           // Enables local lighting for clouds

    #define CLOUD_WIND_SPEED 				0.005   // Wind speed of clouds. [0.0 0.0001 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
    #define CLOUD_PLANE_ALTITUDE 			7000.0  // Altitude of planar clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 cumulusMaxAltitude 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]

    #define CLOUD_CUMULUS_SAMPLES 		   	22      // Sample count for cumulus clouds ray marching. [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 36 40 50 60 100]

    #define CLOUD_CUMULUS_SUNLIGHT_SAMPLES 	4       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
    #define CLOUD_CUMULUS_SKYLIGHT_SAMPLES 	2       // Sample count for skylight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

    #define CLOUD_CUMULUS_ALTITUDE 		   	1000.0  // Altitude of cumulus clouds. [400.0 500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 75000.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CUMULUS_THICKNESS 		2000.0  // Thickness of cumulus clouds. [1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CUMULUS_COVERAGE          1.0     // Coverage of cumulus clouds. [0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0]

//================================================================================================//

const float cumulusMaxAltitude 		= CLOUD_CUMULUS_ALTITUDE + CLOUD_CUMULUS_THICKNESS;
const float cumulusTopOffset        = CLOUD_CUMULUS_THICKNESS * 0.5;

const float cumulusExtinction 		= 0.12;
// const float cumulusScattering 	= 0.12;

const float cirrusExtinction 		= 0.1;
// const float cirrusScattering 	= 0.1;

uniform sampler3D depthtex2;
uniform sampler3D colortex15;

uniform vec3 cloudWindCu;
uniform vec2 cloudWindSc;
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