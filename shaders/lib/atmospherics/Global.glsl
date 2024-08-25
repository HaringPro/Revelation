
float moonlightFactor = fma(abs(moonPhase - 4.0), 0.25, 0.2) * (NIGHT_BRIGHTNESS + nightVision * 0.02);

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers

// const float sunAngularRadius = 0.004675;
const float sunAngularRadius = 0.007; // Unphysical
const float mie_phase_g = 0.78;

#define ATMOSPHERE_BOTTOM_ALTITUDE  1000.0 // [0.0 500.0 1000.0 2000.0 3000.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0 11000.0 12000.0 13000.0 14000.0 15000.0 16000.0]
#define ATMOSPHERE_TOP_ALTITUDE     110000.0 // [0.0 5000.0 10000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 110000.0 120000.0 130000.0 140000.0 150000.0 160000.0]

const float atmosphere_bottom_radius = planetRadius - ATMOSPHERE_BOTTOM_ALTITUDE;
const float atmosphere_top_radius 	 = planetRadius + ATMOSPHERE_TOP_ALTITUDE;

const float atmosphere_bottom_radius_sq = atmosphere_bottom_radius * atmosphere_bottom_radius;
const float atmosphere_top_radius_sq = atmosphere_top_radius * atmosphere_top_radius;

const float isotropicPhase = 0.25 * rPI;

//================================================================================================//

float RayleighPhase(in float mu) {
	const float c = 3.0 / 16.0 * rPI;
	return mu * mu * c + c;
}

// Henyey-Greenstein phase function (HG)
float HenyeyGreensteinPhase(in float mu, in float g) {
	float gg = g * g;
    return isotropicPhase * oneMinus(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
}

// Cornette-Shanks phase function (CS)
float CornetteShanksPhase(in float mu, in float g) {
	float gg = g * g;
  	float pa = oneMinus(gg) * (1.5 / (2.0 + gg));
  	float pb = (1.0 + sqr(mu)) / pow1d5((1.0 + gg - 2.0 * g * mu));

  	return isotropicPhase * pa * pb;
}

// Draine’s phase function
float DrainePhase(in float mu, in float g, in float a) {
	float gg = g * g;
	float pa = oneMinus(gg) / pow1d5(1.0 + gg - 2.0 * g * mu);
	float pb = (1.0 + a * sqr(mu)) / (1.0 + a * (1.0 + 2.0 * gg) / 3.0);
	return isotropicPhase * pa * pb;
}

// Mix between HG and Draine’s phase function (Paper: An Approximate Mie Scattering Function for Fog and Cloud Rendering)
float HG_DrainePhase(in float mu, in float d) {
	float gHG = fastExp(-0.0990567 / (d - 1.67154));
	float gD  = fastExp(-2.20679 / (d + 3.91029) - 0.428934);
	float a   = fastExp(3.62489 - 8.29288 / (d + 5.52825));
	float w   = fastExp(-0.599085 / (d - 0.641583) - 0.665888);

	return mix(HenyeyGreensteinPhase(mu, gHG), DrainePhase(mu, gD, a), w);
}

// Klein-Nishina phase function
float KleinNishinaPhase(in float mu, in float e) {
	return e / (TAU * (e * oneMinus(mu) + 1.0) * log(2.0 * e + 1.0));
}

// CS phase function for clouds
float MiePhaseClouds(in float mu, in vec3 g, in vec3 w) {
	vec3 gg = g * g;
  	vec3 pa = oneMinus(gg) * (1.5 / (2.0 + gg));
	vec3 pb = (1.0 + sqr(mu)) / pow1d5(1.0 + gg - 2.0 * g * mu);

	return isotropicPhase * dot(pa * pb, w);
}

//================================================================================================//

vec2 RaySphereIntersection(in vec3 pos, in vec3 dir, in float rad) {
	float PdotD = dot(pos, dir);
	float delta = sqr(PdotD) - dotSelf(pos) + sqr(rad);

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

mat4x3 ToSphericalHarmonics(in vec3 value, in vec3 dir) {
	const vec2 foo = vec2(0.5 * sqrt(rPI), sqrt(0.75 * rPI));
    vec4 harmonics = vec4(foo.x, foo.y * dir.yzx);

	return mat4x3(value * harmonics.x, value * harmonics.y, value * harmonics.z, value * harmonics.w);
}

vec3 FromSphericalHarmonics(in mat4x3 coeff, in vec3 dir) {
	const vec2 foo = vec2(0.5 * sqrt(rPI), sqrt(0.75 * rPI));
    vec4 harmonics = vec4(foo.x, foo.y * dir.yzx);

	return coeff[0] * harmonics.x + coeff[1] * harmonics.y + coeff[2] * harmonics.z + coeff[3] * harmonics.w;
}

//================================================================================================//

#define VIEWER_BASE_ALTITUDE 64.0 // [0.0 32.0 64.0 128.0 256.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0 262144.0 524288.0 1048576.0 2097152.0 4194304.0 8388608.0 16777216.0 33554432.0 67108864.0 134217728.0 268435456.0 536870912.0 1073741824.0]

float viewerHeight = planetRadius + max(1.0, eyeAltitude + VIEWER_BASE_ALTITUDE);
float horizonCos = rcp(viewerHeight * inversesqrt(viewerHeight * viewerHeight - atmosphere_bottom_radius_sq));
float horizonAngle = fastAcos(horizonCos);

const float scale = oneMinus(4.0 / skyViewRes.x);
const float offset = 2.0 / float(skyViewRes.x);

const vec2 cScale = vec2(skyViewRes.x / (skyViewRes.x + 1.0), 0.5);

// Reference: https://sebh.github.io/publications/egsr2020.pdf
vec3 ToSkyViewLutParams(in vec2 coord) {
	coord *= rcp(cScale);

	// From unit range
	coord.x = fract((coord.x - offset) * rcp(scale));

	// Non-linear mapping of the altitude angle
	coord.y = coord.y < 0.5 ? -sqr(1.0 - 2.0 * coord.y) : sqr(2.0 * coord.y - 1.0);

	float azimuthAngle = coord.x * TAU - PI;
	float altitudeAngle = (coord.y + 1.0) * hPI - horizonAngle;

	float altitudeCos = cos(altitudeAngle);

	return vec3(altitudeCos * sin(azimuthAngle), sin(altitudeAngle), -altitudeCos * cos(azimuthAngle));
}

vec2 FromSkyViewLutParams(in vec3 direction) {
	vec2 coord = normalize(direction.xz);

	float azimuthAngle = atan(coord.x, -coord.y);
	float altitudeAngle = horizonAngle - fastAcos(direction.y);

	coord.x = (azimuthAngle + PI) * rTAU;

	// Non-linear mapping of the altitude angle
	coord.y = 0.5 + 0.5 * fastSign(altitudeAngle) * sqrt(2.0 * rPI * abs(altitudeAngle));

	// To unit range
	coord.x = coord.x * scale + offset;

	return saturate(coord * cScale);
}
