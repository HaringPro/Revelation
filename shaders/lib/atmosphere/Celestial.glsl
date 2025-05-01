
#define SUN_RADIUS_MULT 1.0 // Multiplier of the sun radius (1.0 = real sun radius). [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0]

#define STARS_INTENSITY 0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define STARS_COVERAGE  0.1 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

// #define GALAXY // Enables the rendering of the galaxy
// #define GALAXY_ROTATION // Enables the rotation of the galaxy
#define GALAXY_INTENSITY 0.025 // [0.0 0.005 0.01 0.02 0.025 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

//================================================================================================//

vec3 RenderSun(in vec3 worldDir, in vec3 sunVector) {
    const float cosRadius = cos(atmosphereModel.sun_angular_radius * SUN_RADIUS_MULT);
	const vec3 sunIlluminance = atmosphereModel.solar_irradiance * sunIntensity;
    const vec3 sunRadiance = sunIlluminance / (TAU * oms(cosRadius));

    float cosTheta = dot(worldDir, sunVector);
    if (cosTheta >= cosRadius) {
        // Physical sun model from http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
        const vec3 alpha = vec3(0.397, 0.503, 0.652);

        float centerToEdge = saturate(oms(cosTheta) / oms(cosRadius));
        vec3 factor = pow(vec3(1.0 - centerToEdge * centerToEdge), alpha * 0.5);
        vec3 finalLuminance = sunRadiance * factor;

        return finalLuminance;
    } else {
        // Fake sun bloom
        float offset = cosRadius - cosTheta;
        vec3 sunBloom = sunRadiance / (1.0 + offset * 2e5) * sqr(cosTheta);

        return sunBloom * 1e-3;
    }
}

//================================================================================================//

// Source: https://www.shadertoy.com/view/XtGGRt
vec3 nmzHash33(in vec3 q) {
    uvec3 p = uvec3(ivec3(q));
    p = p * uvec3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
    p = p.yzx * (p.zxy ^ (p >> 3U));
    return vec3(p ^ (p >> 16U)) * rcp(vec3(0xffffffffU));
}

vec3 RenderStars(in vec3 worldDir) {
	vec3 p = rotate(worldDir, worldSunVector, vec3(0.0, 0.0, 1.0));

    vec3 c = vec3(0.0);
    const float res = 768.0;

    for (int i = 0; i < 4; ++i) {
        vec3 q = fract(p * (0.15 * res)) - 0.5;
        vec3 id = floor(p * (0.15 * res));

        vec2 rn = nmzHash33(id).xy;

        float c2 = 1.0 - saturate(length(q) * 2.5);
              c2 *= step(rn.x, STARS_COVERAGE * 0.001 + sqr(i) * 0.001);

        c += c2 * (mix(vec3(1.0, 0.49, 0.1), vec3(0.75, 0.9, 1.0), rn.y) * 0.2 + 0.05);
        p *= 1.3;
    }

    return c * STARS_INTENSITY;
}

//================================================================================================//

uniform sampler2D colortex12;

vec3 RenderGalaxy(in vec3 worldDir) {
    #ifdef GALAXY_ROTATION
        worldDir = rotate(worldDir, worldSunVector, vec3(0.0, 0.0, 1.0));
    #endif

    // Convert to spherical coordinates
    vec2 galacticCoord = sphericalToCartesian(worldDir);
    // Bilinear interpolation is enough
    vec3 galaxy = texture(colortex12, galacticCoord).rgb;
    return sRGBtoLinear(galaxy) * GALAXY_INTENSITY;
}