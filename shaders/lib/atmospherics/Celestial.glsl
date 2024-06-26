
#define STARS_INTENSITY 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define STARS_COVERAGE  0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

#define coneAngleToSolidAngle(x) (TAU * oneMinus(cos(x)))

//================================================================================================//

vec3 RenderSun(in vec3 worldDir, in vec3 sunVector) {
	const vec3 sunIlluminance = vec3(1.0, 0.92549, 0.87843) * 126.6e3;

    float cosTheta = dot(worldDir, sunVector);
    float centerToEdge = saturate(fastAcos(cosTheta) / sunAngularRadius);
    if (cosTheta < cos(sunAngularRadius)) return vec3(0.0);

	const vec3 alpha = vec3(0.429, 0.522, 0.614);

    vec3 factor = pow(vec3(1.0 - centerToEdge * centerToEdge), alpha * 0.5);
    vec3 finalLuminance = sunIlluminance / coneAngleToSolidAngle(sunAngularRadius) * factor;

    return finalLuminance;
}

//================================================================================================//

vec3 RenderMoonReflection(in vec3 worldDir, in vec3 sunVector) {
	float cosTheta = dot(worldDir, -sunVector);

	float disc = curve(saturate((cosTheta - 1.0 + 4e-3) * 3e2));

	return vec3(0.76, 0.9, 1.1) * disc * 0.3;
}

//================================================================================================//

mat3 RotateMatrix(in vec3 x, in vec3 y) {
    float d = dot(x, y);
    float id = 1.0 - d;

    vec3 cr = cross(y, x);
    float s = length(cr);

    vec3 m = cr / s;
    vec3 m2 = m * m * id + d;

    vec3 sm = s * m;
    vec3 w = (m.xy * id).xxy * m.yzz;

    return mat3(
        m2.x      , w.x - sm.z, w.y + sm.y,
        w.x + sm.z, m2.y      , w.z - sm.x,
        w.y - sm.y, w.z + sm.x, m2.z
    );
}

// https://www.shadertoy.com/view/XtGGRt
vec3 nmzHash33(in vec3 q) {
    uvec3 p = uvec3(ivec3(q));
    p = p * uvec3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
    p = p.yzx * (p.zxy ^ (p >> 3U));
    return vec3(p ^ (p >> 16U)) * rcp(vec3(0xffffffffU));
}

vec3 RenderStars(in vec3 worldDir) {
	mat3 rot = RotateMatrix(vec3(0.0, 1.0, 0.0), worldSunVector);
	vec3 p = worldDir * rot;

    vec3 c = vec3(0.0);
    const float res = 768.0;

    for (int i = 0; i < 4; ++i){
        vec3 q = fract(p * (0.15 * res)) - 0.5;
        vec3 id = floor(p * (0.15 * res));

        vec2 rn = nmzHash33(id).xy;

        float c2 = 1.0 - remap(0.0, 0.3, length(q));
              c2 *= step(rn.x, STARS_COVERAGE * 0.01 + sqr(i) * 0.001);

        c += c2 * (mix(vec3(1.0, 0.49, 0.1), vec3(0.75, 0.9, 1.0), rn.y) * 0.25 + 0.05);
        p *= 1.3;
    }

    return c * STARS_INTENSITY;
}
