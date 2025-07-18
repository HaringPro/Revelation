
vec3 fastRefract(in vec3 dir, in vec3 normal, in float eta) {
    float NdotD = dot(normal, dir);
    float k = 1.0 - eta * eta * oms(NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);

    return dir * eta - normal * (sqrt(k) + NdotD * eta);
}

//================================================================================================//

#ifdef RAYTRACED_REFRACTION

vec2 CalculateRefractedCoord(in bool waterMask, in vec3 viewPos, in vec3 viewNormal, in vec3 screenPos) {
	vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, mix(1.0 / GLASS_REFRACT_IOR, 1.0 / WATER_REFRACT_IOR, waterMask));

	vec3 rayPos = screenPos;
	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	if (ScreenSpaceRaytrace(viewPos, refractedDir, dither, RAYTRACE_SAMPLES, rayPos)) {
		rayPos.xy = saturate(rayPos.xy * viewPixelSize);

		float refractedDepth = loadDepth1(uvToTexel(rayPos.xy));
		return mix(screenPos.xy, rayPos.xy, step(screenPos.z, refractedDepth));
	} else {
		return screenPos.xy;
	}
}

#else

vec2 CalculateRefractedCoord(in bool waterMask, in vec3 viewPos, in vec3 viewNormal, in vec3 screenPos, in vec4 gbufferData1, in float transparentDepth) {
	vec2 refractedCoord;
	if (waterMask) {
		vec2 waveNormal = gbufferData1.xy * 2.0 - 1.0;

		waveNormal *= min(transparentDepth, 16.0) * inversesqrt(sdot(viewPos)) * (REFRACTION_STRENGTH * 0.1);
		refractedCoord = waveNormal + screenPos.xy;
	} else {
		vec3 refractedDir = fastRefract(normalize(viewPos), viewNormal, 1.0 / GLASS_REFRACT_IOR);
		refractedDir *= min(transparentDepth, 16.0) * inversesqrt(maxEps(dot(-refractedDir, viewNormal)));

		refractedCoord = ViewToScreenSpace(viewPos + refractedDir * (REFRACTION_STRENGTH * 0.1)).xy;
		vec2 edgeFade = saturate(abs(refractedCoord * 2.0 - 1.0) * 4.0 - 3.0);
		refractedCoord = mix(refractedCoord, screenPos.xy, curve(edgeFade));
	}

	refractedCoord = saturate(refractedCoord);
	float refractedDepth = loadDepth1(uvToTexel(refractedCoord));
	return mix(screenPos.xy, refractedCoord, step(screenPos.z, refractedDepth));
}

#endif