
#define SHADOW_MAP_BIAS	0.9 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

float cubeLength(in vec2 v) {
    vec2 t = abs(cube(v));
    return pow(t.x + t.y, 1.0 / 3.0);
}

float quarticLength(in vec2 v) {
	return sqrt2(pow4(v.x) + pow4(v.y));
}

float DistortionFactor(in vec2 shadowClipPos) {
    return quarticLength(shadowClipPos * 1.165) * SHADOW_MAP_BIAS + 1.0 - SHADOW_MAP_BIAS;
}

vec3 DistortShadowSpace(in vec3 shadowClipPos, in float DistortionFactor) {
	return shadowClipPos * vec3(vec2(rcp(DistortionFactor)), 0.2);
}

vec3 DistortShadowSpace(in vec3 shadowClipPos) {
	float DistortionFactor = DistortionFactor(shadowClipPos.xy);
	return shadowClipPos * vec3(vec2(rcp(DistortionFactor)), 0.2);
}
