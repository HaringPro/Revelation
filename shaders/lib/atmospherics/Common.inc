
float moonlightFactor = fma(abs(moonPhase - 4.0), 0.25, 0.2) * (NIGHT_BRIGHTNESS + nightVision * 0.02);

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers

const float sunAngularRadius = 0.004675;
// const float sunAngularRadius = 0.012; // Unphysical
const float mie_phase_g = 0.78;

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

mat4x3 ToSH(in vec3 value, in vec3 dir) {
	const vec2 foo = vec2(0.5 * sqrt(rPI), sqrt(0.75 * rPI));
    vec4 harmonics = vec4(foo.x, foo.y * dir.yzx);

	return mat4x3(value * harmonics.x, value * harmonics.y, value * harmonics.z, value * harmonics.w);
}

vec3 FromSH(in mat4x3 coeff, in vec3 dir) {
	const vec2 foo = vec2(0.5 * sqrt(rPI), sqrt(0.75 * rPI));
    vec4 harmonics = vec4(foo.x, foo.y * dir.yzx);

	return coeff[0] * harmonics.x + coeff[1] * harmonics.y + coeff[2] * harmonics.z + coeff[3] * harmonics.w;
}

float viewerHeight = planetRadius + max(1.0, eyeAltitude);
float horizonCos = sqrt(viewerHeight * viewerHeight - planetRadius * planetRadius) / viewerHeight;
float horizonAngle = fastAcos(horizonCos);

const float scale = oneMinus(4.0 / skyCaptureRes.x);
const float offset = 2.0 / float(skyCaptureRes.x);

const vec2 cScale = vec2(skyCaptureRes.x / (skyCaptureRes.x + 1.0), 0.5);

// Reference: https://sebh.github.io/publications/egsr2020.pdf
vec3 ToSkyViewLutParams(in vec2 coord) {
	coord *= rcp(cScale);

	coord.x = fract((coord.x - offset) * rcp(scale));

	coord.y = coord.y < 0.5 ? -sqr(1.0 - 2.0 * coord.y) : sqr(2.0 * coord.y - 1.0);

	float azimuthAngle = coord.x * TAU - PI;
	float altitudeAngle = (coord.y + 1.0) * hPI - horizonAngle;

	float altitudeCos = cos(altitudeAngle);

	return vec3(altitudeCos * sin(azimuthAngle), sin(altitudeAngle), -altitudeCos * cos(azimuthAngle));
}

vec2 FromSkyViewLutParams(in vec3 direction) {
	vec2 projectedDir = normalize(direction.xz);

	float azimuthAngle = PI + atan(projectedDir.x, -projectedDir.y);
	float altitudeAngle = horizonAngle - fastAcos(direction.y);

	vec2 coord;
	coord.x = azimuthAngle * rTAU;
	coord.y = 0.5 + 0.5 * sign(altitudeAngle) * sqrt(2.0 * rPI * abs(altitudeAngle));

	coord.x = coord.x * scale + offset;

	return coord * cScale;
}

#include "PrecomputedAtmosphericScattering.glsl"
