
#define RAINBOWS // Enables rainbows
#define RAINBOWS_PRIMARY_INTENSITY 1.0 // Primary rainbow intensity. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0]
#define RAINBOWS_SECONDARY_INTENSITY 1.0 // Secondary rainbow intensity. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0]

//================================================================================================//

vec3 RainbowPhase(float angle, vec3 angleDev) {
	return curve(saturate(1.0 - abs((angleDev - angle) / (angleDev.b - angleDev.r))));
}

vec3 RenderRainbows(float mu) {
    float theta = fastAcos(saturate(-mu));

	// Primary Rainbow
    vec3 phase = RainbowPhase(theta, radians(vec3(42.3, 41.5, 40.6))) * RAINBOWS_PRIMARY_INTENSITY;

	// Secondary Rainbow
    phase += RainbowPhase(theta, radians(vec3(50.1, 51.5, 53.7))) * (RAINBOWS_SECONDARY_INTENSITY * rPI);

    return phase;
}