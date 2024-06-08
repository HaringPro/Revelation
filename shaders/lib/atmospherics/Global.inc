
float moonlightFactor = fma(abs(moonPhase - 4.0), 0.25, 0.2) * (NIGHT_BRIGHTNESS + nightVision * 0.02);

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers

const float sunAngularRadius = 0.004675;
// const float sunAngularRadius = 0.012; // Unphysical
const float mie_phase_g = 0.78;

#define ATMOSPHERE_BOTTOM_ALTITUDE  1000.0 // [0.0 500.0 1000.0 2000.0 3000.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0 11000.0 12000.0 13000.0 14000.0 15000.0 16000.0]
#define ATMOSPHERE_TOP_ALTITUDE     110000.0 // [0.0 5000.0 10000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 110000.0 120000.0 130000.0 140000.0 150000.0 160000.0]

const float atmosphere_bottom_radius = planetRadius - ATMOSPHERE_BOTTOM_ALTITUDE;
const float atmosphere_top_radius = planetRadius + ATMOSPHERE_TOP_ALTITUDE;

const float atmosphere_bottom_radius_sq = atmosphere_bottom_radius * atmosphere_bottom_radius;
const float atmosphere_top_radius_sq = atmosphere_top_radius * atmosphere_top_radius;

//================================================================================================//

float RayleighPhase(in float cosTheta) {
	const float c = 3.0 / 16.0 * rPI;
	return cosTheta * cosTheta * c + c;
}

float HenyeyGreensteinPhase(in float cosTheta, in const float g) {
	const float gg = g * g;
    float phase = 1.0 + gg - 2.0 * g * cosTheta;
    return oneMinus(gg) / (4.0 * PI * phase * sqrt(phase));
}

float CornetteShanksPhase(in float cosTheta, in const float g) {
	const float gg = g * g;
  	float a = oneMinus(gg) * rcp(2.0 + gg) * 3.0 * rPI;
  	float b = (1.0 + sqr(cosTheta)) * pow((1.0 + gg - 2.0 * g * cosTheta), -1.5);
  	return a * b * 0.125;
}

float MiePhaseClouds(in float cosTheta, in const vec3 g, in const vec3 w) {
	const vec3 gg = g * g;
	vec3 a = 0.75 * oneMinus(gg) * rcp(2.0 + gg)/* * rTAU*/;
	vec3 b = (1.0 + sqr(cosTheta)) * pow(1.0 + gg - 2.0 * g * cosTheta, vec3(-1.5));

	return dot(a * b, w) / (w.x + w.y + w.z);
}

vec2 RaySphereIntersection(in vec3 pos, in vec3 dir, in float rad) {
	float PdotD = dot(pos, dir);
	float delta = sqr(PdotD) + sqr(rad) - dotSelf(pos);

	if (delta < 0.0) return vec2(-1.0);

	delta = sqrt(delta);

	return vec2(-delta, delta) - PdotD;
}

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

float viewerHeight = planetRadius + max(1.0, eyeAltitude);
float horizonCos = sqrt(viewerHeight * viewerHeight - atmosphere_bottom_radius_sq) / viewerHeight;
float horizonAngle = fastAcos(horizonCos);

const float scale = oneMinus(4.0 / skyCaptureRes.x);
const float offset = 2.0 / float(skyCaptureRes.x);

const vec2 cScale = vec2(skyCaptureRes.x / (skyCaptureRes.x + 1.0), 0.5);

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
	coord.y = 0.5 + 0.5 * sign(altitudeAngle) * sqrt(2.0 * rPI * abs(altitudeAngle));

	// To unit range
	coord.x = coord.x * scale + offset;

	return saturate(coord * cScale);
}
