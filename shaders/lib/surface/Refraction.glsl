
//#define RAYTRACED_REFRACTION
//#define REFRACTIVE_DISPERSION

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
    float NdotD = dot(normal, dir);
    float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);

    return dir * eta - normal * (fastSqrtN1(k) + NdotD * eta);
}

#ifdef RAYTRACED_REFRACTION

#include "ScreenSpaceRayTracer.glsl"

vec2 CalculateRefractCoord(in TranslucentMask mask, in vec3 normal, in vec3 viewDir, in vec3 viewPos, in float depth, in float ior) {
	if (!mask.translucent) return screenCoord;

	vec3 refractedDir = fastRefract(viewDir, normal, 1.0 / ior);

    vec3 hitPos = vec3(screenCoord, depth);
	if (ScreenSpaceRayTrace(viewPos, refractedDir, InterleavedGradientNoiseTemporal(gl_FragCoord.xy), RAYTRACE_SAMPLES, hitPos)) {
		hitPos.xy *= viewPixelSize;
	} else {
		hitPos.xy = viewToScreenSpace(viewPos + refractedDir * 0.5).xy;
	}

	return saturate(hitPos.xy);
}

#else

#include "/lib/Water/WaterWave.glsl"

vec2 CalculateRefractCoord(in TranslucentMask mask, in vec3 normal, in vec3 worldPos, in vec3 viewPos, in float depth, in float depthT) {
	if (!mask.translucent) return screenCoord;

	vec2 refractCoord;
	float waterDepth = GetDepthLinear(depthT);
	float refractionDepth = GetDepthLinear(depth) - waterDepth;

	if (mask.water) {
        worldPos += cameraPosition;
		vec3 wavesNormal = GetWavesNormal(worldPos.xz - worldPos.y).xzy;
		vec3 waterNormal = mat3(gbufferModelView) * wavesNormal;
		vec3 wavesNormalView = normalize(waterNormal);

		vec3 nv = normalize(gbufferModelView[1].xyz);

		refractCoord = nv.xy - wavesNormalView.xy;
		refractCoord *= saturate(refractionDepth) * 0.5 / (waterDepth + 1e-4);
		refractCoord += screenCoord;
	} else {
		vec3 refractDir = fastRefract(normalize(viewPos), normal, 1.0 / GLASS_REFRACT_IOR);
		refractDir /= saturate(dot(refractDir, -normal));
		refractDir *= saturate(refractionDepth * 2.0) * 0.25;

		refractCoord = viewToScreenSpace(viewPos + refractDir).xy;
	}

	//float currentDepth = texture(depthtex0, screenCoord).x;
	float refractDepth = texture(depthtex1, refractCoord).x;
	if (refractDepth < depthT) return screenCoord;

	return saturate(refractCoord);
}

#endif