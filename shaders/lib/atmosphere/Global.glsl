
//================================================================================================//

// #define PLANET_GROUND

#define ATMOSPHERE_BOTTOM_ALTITUDE  0.0 // [0.0 500.0 1000.0 2000.0 3000.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0 11000.0 12000.0 13000.0 14000.0 15000.0 16000.0]
#define ATMOSPHERE_TOP_ALTITUDE     100000.0 // [0.0 5000.0 10000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 110000.0 120000.0 130000.0 140000.0 150000.0 160000.0]

#define VIEWER_BASE_ALTITUDE        64.0 // [0.0 32.0 64.0 128.0 256.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0 262144.0 524288.0 1048576.0 2097152.0 4194304.0 8388608.0 16777216.0 33554432.0 67108864.0 134217728.0 268435456.0 536870912.0 1073741824.0]

//================================================================================================//

struct AtmosphereParameters {
    // The solar irradiance at the top of the atmosphere.
    vec3 solar_irradiance;
    // The sun's angular radius. Warning: the implementation uses approximations
    // that are valid only if this angle is smaller than 0.1 radians.
   float sun_angular_radius;
    // The distance between the planet center and the bottom of the atmosphere.
   float bottom_radius;
    // The distance between the planet center and the top of the atmosphere.
   float top_radius;
    // The density profile of air molecules, i.e. a function from altitude to
    // dimensionless values between 0 (null density) and 1 (maximum density).
//    DensityProfile rayleigh_density;
    // The scattering coefficient of air molecules at the altitude where their
    // density is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The scattering coefficient at altitude h is equal to
    // 'rayleigh_scattering' times 'rayleigh_density' at this altitude.
    vec3 rayleigh_scattering;
    // The density profile of aerosols, i.e. a function from altitude to
    // dimensionless values between 0 (null density) and 1 (maximum density).
//    DensityProfile mie_density;
    // The scattering coefficient of aerosols at the altitude where their density
    // is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The scattering coefficient at altitude h is equal to
    // 'mie_scattering' times 'mie_density' at this altitude.
    vec3 mie_scattering;
    // The extinction coefficient of aerosols at the altitude where their density
    // is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The extinction coefficient at altitude h is equal to
    // 'mie_extinction' times 'mie_density' at this altitude.
   vec3 mie_extinction;
    // The asymetry parameter for the Cornette-Shanks phase function for the
    // aerosols.
//    float mie_phase_function_g;
    // The density profile of air molecules that absorb light (e.g. ozone), i.e.
    // a function from altitude to dimensionless values between 0 (null density)
    // and 1 (maximum density).
//    DensityProfile absorption_density;
    // The extinction coefficient of molecules that absorb light (e.g. ozone) at
    // the altitude where their density is maximum, as a function of wavelength.
    // The extinction coefficient at altitude h is equal to
    // 'absorption_extinction' times 'absorption_density' at this altitude.
//    vec3 absorption_extinction;
    // The average albedo of the ground.
    vec3 ground_albedo;
    // The cosine of the maximum Sun zenith angle for which atmospheric scattering
    // must be precomputed (for maximum precision, use the smallest Sun zenith
    // angle yielding negligible sky light radiance values. For instance, for the
    // Earth case, 102 degrees is a good choice - yielding mu_s_min = -0.2).
   float mu_s_min;
};

//================================================================================================//

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers
const float mie_phase_g = 0.78;

float viewerHeight = planetRadius + max(1.0, eyeAltitude + VIEWER_BASE_ALTITUDE);
float moonlightMult = fma(abs(moonPhase - 4.0), 0.25, 0.2) * (NIGHT_BRIGHTNESS + nightVision * 0.02);

// Values from https://github.com/ebruneton/precomputed_atmospheric_scattering
const int kLambdaMin = 360;

const float kSolarIrradiance[48] = {
    1.11776, 1.14259, 1.01249, 1.14716, 1.72765, 1.73054, 1.6887, 1.61253,
    1.91198, 2.03474, 2.02042, 2.02212, 1.93377, 1.95809, 1.91686, 1.8298,
    1.8685, 1.8931, 1.85149, 1.8504, 1.8341, 1.8345, 1.8147, 1.78158, 1.7533,
    1.6965, 1.68194, 1.64654, 1.6048, 1.52143, 1.55622, 1.5113, 1.474, 1.4482,
    1.41018, 1.36775, 1.34188, 1.31429, 1.28303, 1.26758, 1.2367, 1.2082,
    1.18737, 1.14683, 1.12362, 1.1058, 1.07124, 1.04992
};

const AtmosphereParameters atmosphereModel = AtmosphereParameters(
	vec3(1.0),
    // vec3(1.474000, 1.850400, 1.911980),
    // vec3(
    //     kSolarIrradiance[(660 - kLambdaMin) / 10],
    //     kSolarIrradiance[(550 - kLambdaMin) / 10],
    //     kSolarIrradiance[(440 - kLambdaMin) / 10]
    // ),
	0.004675,
    planetRadius - ATMOSPHERE_BOTTOM_ALTITUDE,
    planetRadius + ATMOSPHERE_TOP_ALTITUDE,
//    DensityProfile(DensityProfileLayer[2](DensityProfileLayer(0.000000,0.000000,0.000000,0.000000,0.000000),DensityProfileLayer(0.000000,1.000000,-0.125000,0.000000,0.000000))),
    vec3(0.005802, 0.013558, 0.033100),
//    DensityProfile(DensityProfileLayer[2](DensityProfileLayer(0.000000,0.000000,0.000000,0.000000,0.000000),DensityProfileLayer(0.000000,1.000000,-0.833333,0.000000,0.000000))),
    vec3(0.003996, 0.003996, 0.003996),
   vec3(0.004440, 0.004440, 0.004440),
//    0.800000,
//    DensityProfile(DensityProfileLayer[2](DensityProfileLayer(25.000000,0.000000,0.000000,0.066667,-0.666667),DensityProfileLayer(0.000000,0.000000,0.000000,-0.066667,2.666667))),
//    vec3(0.000650, 0.001881, 0.000085),
    vec3(0.5),
   -0.2
);

const float atmosphere_bottom_radius_sq = atmosphereModel.bottom_radius * atmosphereModel.bottom_radius;
const float atmosphere_top_radius_sq    = atmosphereModel.top_radius * atmosphereModel.top_radius;

#if 1
const vec3 SKY_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3(683.0, 683.0, 683.0) * 1e-3;
const vec3 SUN_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3(126600.0, 126600.0, 126600.0) * 1e-3;
#else
// Values generated by https://github.com/ebruneton/precomputed_atmospheric_scattering
const vec3 SKY_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3(114974.916437f, 71305.954816f, 65310.548555f) * 1e-3;
const vec3 SUN_SPECTRAL_RADIANCE_TO_LUMINANCE = vec3(98242.786222, 69954.398112, 66475.012354) * 1e-3;
#endif

//================================================================================================//

const float uniformPhase = 0.25 * rPI;

float RayleighPhase(in float mu) {
	const float c = 3.0 / 16.0 * rPI;
	return mu * mu * c + c;
}

// Henyey-Greenstein phase function (HG)
float HenyeyGreensteinPhase(in float mu, in float g) {
	float gg = g * g;
    return uniformPhase * oms(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
}

// Cornette-Shanks phase function (CS)
float CornetteShanksPhase(in float mu, in float g) {
	float gg = g * g;
  	float pa = oms(gg) * (1.5 / (2.0 + gg));
  	float pb = (1.0 + sqr(mu)) / pow1d5((1.0 + gg - 2.0 * g * mu));

  	return uniformPhase * pa * pb;
}

// Draine’s phase function
float DrainePhase(in float mu, in float g, in float a) {
	float gg = g * g;
	float pa = oms(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
	float pb = (1.0 + a * sqr(mu)) / (1.0 + a * (1.0 + 2.0 * gg) / 3.0);
	return uniformPhase * pa * pb;
}

// Mix between HG and Draine’s phase function (Paper: An Approximate Mie Scattering Function for Fog and Cloud Rendering)
// d is the water droplet diameters in µm
float HgDrainePhase(in float mu, in float d) {
	float gHG = fastExp(-0.0990567 / (d - 1.67154));
	float gD  = fastExp(-2.20679 / (d + 3.91029) - 0.428934);
	float a   = fastExp(3.62489 - 8.29288 / (d + 5.52825));
	float w   = fastExp(-0.599085 / (d - 0.641583) - 0.665888);

	return mix(HenyeyGreensteinPhase(mu, gHG), DrainePhase(mu, gD, a), w);
}

// Klein-Nishina phase function
float KleinNishinaPhase(in float mu, in float e) {
	return e / (TAU * (e * oms(mu) + 1.0) * log(2.0 * e + 1.0));
}

//================================================================================================//

vec2 RaySphereIntersection(in vec3 pos, in vec3 dir, in float rad) {
	float PdotD = dot(pos, dir);
	float delta = sqr(PdotD) - sdot(pos) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - PdotD;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphereIntersection(in float r, in float mu, in float rad) {
	float delta = sqr(r) * (sqr(mu) - 1.0) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - r * mu;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(in vec3 pos, in vec3 dir, in float bottomRad, in float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(pos, dir, bottomRad);
    vec2 topIntersection = RaySphereIntersection(pos, dir, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(in float r, in float mu, in float bottomRad, in float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(r, mu, bottomRad);
    vec2 topIntersection = RaySphereIntersection(r, mu, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

//================================================================================================//

const float scale = oms(4.0 / skyViewRes.x);
const float offset = 2.0 / float(skyViewRes.x);

// Reference: https://sebh.github.io/publications/egsr2020.pdf
vec3 ToSkyViewLutParams(in vec2 coord) {
	coord.y *= 2.0;

	// From unit range
	coord.x = fract((coord.x - offset) * rcp(scale));

	// Non-linear mapping of the altitude angle
	coord.y = coord.y < 0.5 ? -sqr(1.0 - 2.0 * coord.y) : sqr(2.0 * coord.y - 1.0);

    float horizonCos = rcp(viewerHeight * inversesqrt(viewerHeight * viewerHeight - atmosphere_bottom_radius_sq));
    float horizonAngle = fastAcos(horizonCos);

	float azimuthAngle = coord.x * TAU - PI;
	float altitudeAngle = (coord.y + 1.0) * hPI - horizonAngle;

	float altitudeCos = cos(altitudeAngle);

	return vec3(altitudeCos * sin(azimuthAngle), sin(altitudeAngle), -altitudeCos * cos(azimuthAngle));
}

vec2 FromSkyViewLutParams(in vec3 direction) {
	vec2 coord = normalize(direction.xz);

    float horizonCos = rcp(viewerHeight * inversesqrt(viewerHeight * viewerHeight - atmosphere_bottom_radius_sq));
    float horizonAngle = fastAcos(horizonCos);

	float azimuthAngle = atan(coord.x, -coord.y);
	float altitudeAngle = horizonAngle - fastAcos(direction.y);

	coord.x = (azimuthAngle + PI) * rTAU;

	// Non-linear mapping of the altitude angle
	coord.y = 0.5 + 0.5 * fastSign(altitudeAngle) * sqrt(2.0 * rPI * abs(altitudeAngle));

	// To unit range
	coord.x = coord.x * scale + offset;

	return saturate(coord * vec2(1.0, 0.5));
}
