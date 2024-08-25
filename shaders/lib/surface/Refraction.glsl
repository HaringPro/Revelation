
// #define RAYTRACED_REFRACTION
#define REFRACTION_STRENGTH 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.5 6.0 6.5 7.0 7.5 8.0 9.5 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0]

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
    float NdotD = dot(normal, dir);
    float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);

    return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

//================================================================================================//

#ifdef RAYTRACED_REFRACTION

vec2 CalculateRefractCoord(in vec3 viewPos, in vec3 viewNormal, in vec3 hitPos) {
	// if (materialID != 2u && materialID != 3u) return screenCoord;

	vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);

	if (ScreenSpaceRaytrace(viewPos, refractedDir, BlueNoiseTemporal(ivec2(gl_FragCoord.xy)), RAYTRACE_SAMPLES, hitPos)) {
		hitPos.xy *= viewPixelSize;
	} else {
		refractedDir /= saturate(dot(refractedDir, -viewNormal));
		hitPos.xy = ViewToScreenSpace(viewPos + refractedDir * 0.5).xy;
	}

	return saturate(hitPos.xy);
}

#else

vec2 CalculateRefractCoord(in uint materialID, in vec3 viewPos, in vec3 viewNormal, in vec4 gbufferData1, in float transparentDepth) {
	// if (materialID != 2u && materialID != 3u) return screenCoord;

	vec2 refractCoord;
	if (materialID == 3u) {
		vec2 waveNormal = unpackUnorm2x8(gbufferData1.x) * 2.0 - 1.0;
		vec3 waveNormalView = normalize(mat3(gbufferModelView) * vec3(waveNormal, 1.0).xzy);

		vec3 nv = normalize(gbufferModelView[1].xyz);

		refractCoord = nv.xy - waveNormalView.xy;
		refractCoord *= saturate(transparentDepth / (1.0 - viewPos.z)) * REFRACTION_STRENGTH * 0.2;
		refractCoord += screenCoord;
	} else {
		vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);
		refractedDir *= saturate(transparentDepth * 0.1) / saturate(dot(refractedDir, -viewNormal));

		refractCoord = ViewToScreenSpace(viewPos + refractedDir * REFRACTION_STRENGTH).xy;
	}

	return saturate(refractCoord);
}

#endif