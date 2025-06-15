
#define RAINBOWS // Enables rainbows
#define RAINBOWS_PRIMARY_INTENSITY 1.0 // Primary rainbow intensity. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0]
#define RAINBOWS_SECONDARY_INTENSITY 1.0 // Secondary rainbow intensity. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0]

//================================================================================================//

vec3 RainbowPhase(in float angle, in vec3 angleDev, in float falloff) {
    return exp2(-falloff * sqr(angle - angleDev * (PI / 180.0)));
}

vec3 RenderRainbows(in float mu, in float d) {
    float theta = fastAcos(saturate(-mu));

	// Primary Rainbow
    vec3 phase = RainbowPhase(theta, vec3(42.3 - 0.25, 41.5, 40.6 + 0.35), 8192.0) * RAINBOWS_PRIMARY_INTENSITY;

	// Secondary Rainbow
    phase += RainbowPhase(theta, vec3(50.1 + 0.75, 51.5, 53.7 - 1.0), 2048.0) * (RAINBOWS_SECONDARY_INTENSITY * rPI);

	// Distance Fade
    phase *= smoothstep(256.0, 384.0, d);

    return phase * 1e-2;
}