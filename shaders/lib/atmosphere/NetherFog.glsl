#if !defined INCLUDE_LIB_ATMOSPHERE_NETHER_FOG
#define INCLUDE_LIB_ATMOSPHERE_NETHER_FOG

//================================================================================================//

float CalculateFogDensity(vec3 rayPos) {
	rayPos += cameraPosition;

	float density = exp2(abs(rayPos.y - 64.0) * -rcp(32.0));
	vec3 windOffset = vec3(0.01, 0.02, 0.01) * frameTimeCounter;

	rayPos *= vec3(0.04, 0.02, 0.04);
    rayPos.xz -= sqr(rayPos.y * 0.25);
	rayPos -= windOffset;

    float shape = texture(noisetex, rayPos.xz * 0.1).z;

    vec3 curlNoise = texture(curlNoise3D, rayPos * 2.0 + windOffset).xyz;
    rayPos += curlNoise * shape;

    float erosion = texture(baseNoiseTex, rayPos - windOffset).x;
	density *= 1.0 - shape - erosion;

	return sqr(saturate(density)) + 0.005;
}

//================================================================================================//

mat2x3 RaymarchNetherFog(vec3 rayStart, vec3 rayEnd, float dither, uint steps) {
	float rayLength = sdot(rayEnd - rayStart);
	float norm = inversesqrt(rayLength);
	rayLength *= norm;

	vec3 rayDir = (rayEnd - rayStart) * norm;

	float maxDist = min(128.0, lodRenderDist);
	rayLength = min(rayLength, maxDist);

    float stepCount = float(steps);
    float stepInverse = 1.0 / stepCount;

	vec3 fogExtinctionCoeff = vec3(1.0);
	vec3 fogScatteringCoeff = netherColorCustom;

	vec3 scattering = vec3(0.0);
	vec3 transmittance = vec3(1.0);

    for (float i = 0.0; i < stepCount; ++i) {
        vec2 t01 = vec2(i, i + 1.0) * stepInverse;

        // Square distribution
        t01 *= t01;
        t01 *= rayLength;

        float t = mix(t01.x, t01.y, dither);
        float dt = t01.y - t01.x;

		vec3 rayPos = rayStart + rayDir * t;

		float stepDensity = CalculateFogDensity(rayPos);

		vec3 stepExtinction = fogExtinctionCoeff * stepDensity;
		vec3 stepTransmittance = exp(-dt * stepExtinction);

		vec3 stepIntegral = transmittance * oms(stepTransmittance) / maxEps(stepExtinction);
		scattering += fogScatteringCoeff * stepDensity * stepIntegral;

		transmittance *= stepTransmittance;

		// Break if the transmittance is too small (optimization)
		if (dot(transmittance, vec3(1.0)) < 1e-3) break;
	}

	return mat2x3(scattering, transmittance);
}

#endif // INCLUDE_LIB_ATMOSPHERE_NETHER_FOG
