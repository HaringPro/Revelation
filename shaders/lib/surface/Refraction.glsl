
// #define RAYTRACED_REFRACTION

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
    float NdotD = dot(normal, dir);
    float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);

    return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

#ifdef RAYTRACED_REFRACTION

vec2 CalculateRefractCoord(in vec3 viewPos, in vec3 viewNormal, in vec3 hitPos) {
	// if (materialID != 2u && materialID != 3u) return screenCoord;

	vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);

	if (ScreenSpaceRaytrace(viewPos, refractedDir, BlueNoiseTemporal(ivec2(gl_FragCoord.xy)), RAYTRACE_SAMPLES, hitPos)) {
		hitPos.xy *= viewPixelSize;
	} else {
		refractedDir /= saturate(dot(refractedDir, -viewNormal));
		hitPos.xy = ViewToScreenSpace(viewPos + refractedDir * 0.4).xy;
	}

	return saturate(hitPos.xy);
}

#else

#include "/lib/water/WaterWave.glsl"

vec2 CalculateRefractCoord(in uint materialID, in vec3 viewPos, in vec3 viewNormal, in vec4 gbufferData1, in float transparentDepth) {
	// if (materialID != 2u && materialID != 3u) return screenCoord;

	vec2 refractCoord;
	if (materialID == 3u) {
		vec2 waveNormal = unpackUnorm2x8(gbufferData1.x) * 2.0 - 1.0;
		vec3 waveNormalView = normalize(mat3(gbufferModelView) * vec3(waveNormal, 1.0).xzy);

		vec3 nv = normalize(gbufferModelView[1].xyz);

		refractCoord = nv.xy - waveNormalView.xy;
		refractCoord *= saturate(transparentDepth) * 0.5 / (1e-4 - viewPos.z);
		refractCoord += screenCoord;
	} else {
		vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);
		refractedDir *= saturate(transparentDepth) * 0.4 / saturate(dot(refractedDir, -viewNormal));

		refractCoord = ViewToScreenSpace(viewPos + refractedDir).xy;
	}

	return saturate(refractCoord);
}

#endif