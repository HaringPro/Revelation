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

    #define CLOUD_WIND_SPEED 			0.005   // Wind speed of clouds. [0.0 0.0001 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]

    #define CLOUD_MS_COUNT              4       // Times of multi-scattering for clouds. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50]
    #define CLOUD_MS_FALLOFF_S          0.5     // Scattering falloff for multi-scattering. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
    #define CLOUD_MS_FALLOFF_E          0.5     // Extinction falloff for multi-scattering. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
    #define CLOUD_MS_FALLOFF_P          0.5     // Asymmetry falloff for multi-scattering. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Low-level clouds */
    #define CLOUD_CUMULUS 	                    // Enables cumulus clouds

	#ifndef CLOUD_CUMULUS
		#undef CLOUD_SHADOWS
	#endif

    #define CLOUD_CU_SAMPLES 		   	32      // Sample count for cumulus clouds ray marching. [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 36 40 44 48 50 52 56 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200 210 220 230 240 250 260 270 280 290 300 310 320 330 340 350 360 370 380 390 400 410 420 430 440 450 460 470 480 490 500]

    #define CLOUD_CU_SUNLIGHT_SAMPLES 	5       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
    #define CLOUD_CU_SKYLIGHT_SAMPLES 	0       // Sample count for skylight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

    #define CLOUD_CU_ALTITUDE 		   	800.0   // Altitude of cumulus clouds. [400.0 500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 75000.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_THICKNESS 		    1500.0  // Thickness of cumulus clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_CU_COVERAGE           0.5     // Coverage of cumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Mid-level clouds */
    #define CLOUD_MID_ALTITUDE 			4000.0  // Altitude of mid clouds.  [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_MID_THICKNESS 		3000.0  // Thickness of mid clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_MID_SUNLIGHT_SAMPLES 	3       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

//  #define CLOUD_ALTOSTRATUS                   // Enables altostratus clouds
    #define CLOUD_AS_COVERAGE           0.6     // Coverage of altostratus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* High-level clouds */
    #define CLOUD_HIGH_ALTITUDE 		7000.0  // Altitude of high clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]
    #define CLOUD_HIGH_THICKNESS 		2000.0  // Thickness of high clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1450.0 1500.0 1550.0 1600.0 1650.0 1700.0 1750.0 1800.0 1850.0 1900.0 1950.0 2000.0 2050.0 2100.0 2150.0 2200.0 2250.0 2300.0 2350.0 2400.0 2450.0 2500.0 2550.0 2600.0 2650.0 2700.0 2750.0 2800.0 2850.0 2900.0 2950.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0]
    #define CLOUD_HIGH_SUNLIGHT_SAMPLES 3       // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

    #define CLOUD_CIRRUS 	                    // Enables cirrus clouds
    #define CLOUD_CI_COVERAGE           0.65    // Coverage of cirrus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

    #define CLOUD_CIRROCUMULUS                  // Enables cirrocumulus clouds
    #define CLOUD_CC_COVERAGE           0.6     // Coverage of cirrocumulus clouds. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

/* Cloud shadows */
	#if defined DISTANT_HORIZONS
		#define CSD_INF float(dhRenderDistance)
	#else
		#define CSD_INF far
	#endif
    #define CLOUD_SHADOW_DISTANCE 		256.0   // Render distance of cloud shadows. [CSD_INF 32.0 64.0 128.0 256.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0]
    #define CLOUD_SHADOW_SAMPLES 	    20      // Sample count for cloud shadows. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50]

/* Crepuscular rays */
    #define CREPUSCULAR_RAYS                    // Enables crepuscular rays
    #define CREPUSCULAR_RAYS_SAMPLES    16      // Sample count for crepuscular rays. [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
    #define CREPUSCULAR_RAYS_INTENSITY  1.0     // Intensity of crepuscular rays. [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0 5.1 5.2 5.3 5.4 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 18.5 19.0 19.5 20.0 20.5 21.0 21.5 22.0 22.5 23.0 23.5 24.0 24.5 25.0]


//================================================================================================//

const uint  cloudMsCount 			= CLOUD_MS_COUNT;

// Must be a <= b to keep energy conservation
const float cloudMsFalloffA 	    = CLOUD_MS_FALLOFF_S;
const float cloudMsFalloffB 	    = CLOUD_MS_FALLOFF_E;
const float cloudMsFalloffC 	    = CLOUD_MS_FALLOFF_P;

const float cloudMapCovDist 		= 256e3; // m

// TODO: Provide adjustable options for these parameters
const float cloudForwardG 		    = 0.7;
const float cloudBackwardG 		    = -0.3;
const float cloudLobeMixer          = 0.4;
const float cloudSilverG 		    = 0.9;
const float cloudSilverI 	        = 0.3;

const float cumulusTopAltitude 		= CLOUD_CU_ALTITUDE + CLOUD_CU_THICKNESS;
const float cumulusTopOffset        = 500.0;

const float cumulusBottomRadius     = planetRadius + CLOUD_CU_ALTITUDE;
const float cumulusTopRadius        = planetRadius + cumulusTopAltitude;

const float cloudMidRadius          = planetRadius + CLOUD_MID_ALTITUDE;
const float cloudHighRadius         = planetRadius + CLOUD_HIGH_ALTITUDE;

const float cumulusScattering 		= 0.08;
const float stratusScattering 		= 0.05;
const float cirrusScattering 		= 0.02;

const float cumulusAbsorption 		= 0.0;
const float stratusAbsorption 		= 0.0;
const float cirrusAbsorption 		= 0.0;

const float cumulusExtinction 		= cumulusScattering + cumulusAbsorption;
const float stratusExtinction 		= stratusScattering + stratusAbsorption;
const float cirrusExtinction 		= cirrusScattering + cirrusAbsorption;

const float cumulusAlbedo 		    = cumulusScattering / cumulusExtinction;
const float stratusAlbedo 		    = stratusScattering / stratusExtinction;
const float cirrusAlbedo 		    = cirrusScattering / cirrusExtinction;

const float minCloudTransmittance   = 0.05;

//================================================================================================//

#define baseNoiseTex    depthtex2  // 3D perlin-worley & fBm worley noise texture
#define detailNoiseTex  colortex15 // 3D fBm worley noise texture

uniform sampler3D baseNoiseTex;
uniform sampler3D detailNoiseTex;

uniform vec3 cloudWindCu;
uniform vec2 cloudWindAs;
uniform vec2 cloudWindCc;
uniform vec2 cloudWindCi;
uniform vec3 cloudLightVector;

//================================================================================================//

// Quadratic polynomial smooth-min function from https://www.iquilezles.org/www/articles/smin/smin.htm
float smin(float a, float b, float k) {
    k *= 4.0;
    float h = max0(k - abs(a - b)) / k;
    return min(a, b) - h * h * k * 0.25;
}

// From [Schneider, 2015]
float remap(float value, float orignalMin, float orignalMax, float newMin, float newMax) {
    return newMin + saturate((value - orignalMin) / (orignalMax - orignalMin)) * (newMax - newMin);
}

// Triple-Lobe CS phase function for clouds
float MiePhaseClouds(in float mu, in vec3 g, in vec3 w) {
	vec3 gg = g * g;
  	vec3 pa = oms(gg) * (1.5 / (2.0 + gg));
	vec3 pb = (1.0 + sqr(mu)) / pow1d5(1.0 + gg - 2.0 * g * mu);

	return uniformPhase * dot(pa * pb, w);
}

// Dual-Lobe HG phase function
// g0: forward lobe anisotropy parameter, g1: backward lobe anisotropy parameter
// m: mixing parameter
float DualLobePhase(in float mu, in float g0, in float g1, in float m){
    return mix(HenyeyGreensteinPhase(mu, g0), HenyeyGreensteinPhase(mu, g1), m);
}

// Triple-Lobe HG phase function
// g0: forward lobe anisotropy parameter, g1: backward lobe anisotropy parameter
// m: mixing parameter, g2: peak anisotropy parameter, i: peak intensity
float TripleLobePhase(in float mu, in float g0, in float g1, in float m, in float g2, in float i){
    float p = mix(HenyeyGreensteinPhase(mu, g0), HenyeyGreensteinPhase(mu, g1), m);
    return max(p, HenyeyGreensteinPhase(mu, g2) * i);
}

#endif