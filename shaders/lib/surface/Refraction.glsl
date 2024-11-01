
// #define RAYTRACED_REFRACTION // WIP
#define REFRACTION_STRENGTH 0.5 // [0.0 0.1 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 3.8 4.0 4.2 4.4 4.6 4.8 5.0 5.5 6.0 6.5 7.0 7.5 8.0 9.5 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0]

vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
    float NdotD = dot(normal, dir);
    float k = 1.0 - eta * eta * oneMinus(NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);

    return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

//================================================================================================//

#ifdef RAYTRACED_REFRACTION

vec2 CalculateRefractedCoord(in bool waterMask, in vec3 viewPos, in vec3 viewNormal, in vec3 screenPos) {
	vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / mix(GLASS_REFRACT_IOR, WATER_REFRACT_IOR, waterMask));

	vec3 rayPos = screenPos;
	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	if (ScreenSpaceRaytrace(viewPos, refractedDir, dither, RAYTRACE_SAMPLES, rayPos)) {
		rayPos.xy *= viewPixelSize;
	} else {
		refractedDir *= inversesqrt(maxEps(dot(-refractedDir, viewNormal)));
		rayPos.xy = ViewToScreenSpace(viewPos + refractedDir * REFRACTION_STRENGTH * 0.1).xy;
	}

	vec2 edgeFade = saturate(abs(rayPos.xy * 2.0 - 1.0) * 4.0 - 3.0);
	rayPos.xy = mix(rayPos.xy, screenPos.xy, curve(edgeFade));

	rayPos.xy = saturate(rayPos.xy);
	float refractedDepth = readDepth1(uvToTexel(rayPos.xy));
	return refractedDepth < screenPos.z ? screenPos.xy : rayPos.xy;
}

#else

vec2 CalculateRefractedCoord(in bool waterMask, in vec3 viewPos, in vec3 viewNormal, in vec3 screenPos, in vec4 gbufferData1, in float transparentDepth) {
	vec2 refractedCoord;
	if (waterMask) {
		vec2 waveNormal = gbufferData1.xy * 2.0 - 1.0;

		waveNormal *= min(transparentDepth, 16.0) * inversesqrt(dotSelf(viewPos)) * (REFRACTION_STRENGTH * 0.1);
		refractedCoord = waveNormal + screenPos.xy;
	} else {
		vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);
		refractedDir *= min(transparentDepth, 16.0) * inversesqrt(maxEps(dot(-refractedDir, viewNormal)));

		refractedCoord = ViewToScreenSpace(viewPos + refractedDir * REFRACTION_STRENGTH * 0.1).xy;
		vec2 edgeFade = saturate(abs(refractedCoord * 2.0 - 1.0) * 4.0 - 3.0);
		refractedCoord = mix(refractedCoord, screenPos.xy, curve(edgeFade));
	}

	refractedCoord = saturate(refractedCoord);
	float refractedDepth = readDepth1(uvToTexel(refractedCoord));
	return refractedDepth < screenPos.z ? screenPos.xy : refractedCoord;
}

#endif