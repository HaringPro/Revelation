// Method from GeForceLegend
// https://discord.com/channels/237199950235041794/525510804494221312/1379718853872848896

#define SHADOW_DISTORTION_STRENGTH 4.0 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0]

float CalcDistortionFactor(in vec2 shadowClipPos) {
	float invClipLength = inversesqrt(sdot(shadowClipPos));
	float distortionCurve = log((exp(SHADOW_DISTORTION_STRENGTH) - 1.0) / invClipLength + 1.0);
    return distortionCurve * invClipLength * rcp(SHADOW_DISTORTION_STRENGTH);
}

vec3 DistortShadowSpace(in vec3 shadowClipPos, in float distortionFactor) {
	return shadowClipPos * vec3(vec2(distortionFactor), 0.2);
}

vec3 DistortShadowSpace(in vec3 shadowClipPos) {
	float distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
	return shadowClipPos * vec3(vec2(distortionFactor), 0.2);
}