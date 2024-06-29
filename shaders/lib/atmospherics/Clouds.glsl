// Referrence: 
// https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn
// http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/

#define CLOUDS_WIND_SPEED 0.005 // Wind speed of clouds. [0.0 0.0001 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
#define CLOUD_PLANE_ALTITUDE 3000.0 // Altitude of planar clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]

//================================================================================================//

void ToPlanetCurvePos(inout vec3 pos) {
	pos.y += planetRadius;
	pos.y = length(pos) - planetRadius;
}

//================================================================================================//

float GetSmoothNoise(in vec2 coord) {
    // coord *= 256.0;
    vec2 whole = floor(coord);
    vec2 part = curve(coord - whole);

	ivec2 texel = ivec2(whole);

	float s0 = texelFetch(noisetex, texel % 256, 0).x;
	float s1 = texelFetch(noisetex, (texel + ivec2(1, 0)) % 256, 0).x;
	float s2 = texelFetch(noisetex, (texel + ivec2(0, 1)) % 256, 0).x;
	float s3 = texelFetch(noisetex, (texel + ivec2(1, 1)) % 256, 0).x;

    return mix(mix(s0, s1, part.x), mix(s2, s3, part.x), part.y);
}

float CloudPlaneDensity(in vec2 worldPos) {
	vec2 wind = cloudWind.xz * CLOUDS_WIND_SPEED;
	float localCoverage = GetSmoothNoise(worldPos * 1e-4 - wind);

	/* Sratocumulus clouds */
	vec2 position = worldPos * 6e-4 - wind;

	float sratocumulus = texture(noisetex, position * 0.005).z, weight = 0.5;

	for (uint i = 0u; i < 6u; ++i, weight *= 0.5) {
		sratocumulus += weight * textureLod(noisetex, position * 5e-3 + sratocumulus * 0.05, 0.0).x;
		position = position * (3.0 + max0(float(i) - 4.0)) - wind;
	}

	sratocumulus = saturate(sratocumulus * 0.2 + localCoverage * 0.2 + wetness * 4e-2 - 0.32) * 0.4;

	/* Cirrus clouds */
	position = worldPos * 6e-7 - wind * 6e-3;
	weight = 0.5;
	float cirrus = texture(noisetex, position).x;

	for (uint i = 1u; i < 6u; ++i, weight *= 0.5) {
		position *= vec2(2.0, 3.0) + vec2(i & 1u, i & 0u);
        position -= wind * 6e-3;
		cirrus += texture(noisetex, position + curve(cirrus * 0.2) * 0.3).x * weight;
	}

    cirrus = pow4(clamp(cirrus * 0.7 - saturate(localCoverage * 2.4 - 0.8) - 0.55, 0.0, 0.28) * cirrus);

	return saturate(cirrus + sratocumulus);
}

vec4 RenderCloudPlane(in float stepT, in vec2 worldPos, in vec2 worldDir, in float LdotV, in float lightNoise, in vec4 phases) {
	float density = CloudPlaneDensity(worldPos);
	if (density > 1e-6) {
		// Siggraph 2017's new formula
		float opticalDepth = density * stepT;
		float absorption = oneMinus(max(fastExp(-opticalDepth), fastExp(-opticalDepth * 0.25) * 0.7));

		float rayLength = 24.0;
		vec2 rayPos = worldPos;
		vec3 rayStep = vec3(worldLightVector.xz, 1.0) * rayLength;
		// float lightNoise = hash1(worldPos);

		opticalDepth = 0.0;
		// Compute the optical depth of sunlight through clouds
		for (uint i = 0u; i < 4u; ++i, rayPos += rayStep.xy) {
			float density = CloudPlaneDensity(rayPos + rayStep.xy * lightNoise);
			if (density < 1e-6) continue;

			rayStep *= 2.0;

			opticalDepth += density * rayStep.z;
		} opticalDepth = min(opticalDepth, 16.0);

		// Compute sunlight muti-scattering
		float scatteringSun =  fastExp(-opticalDepth * 1.0)  * phases.x;
			scatteringSun += fastExp(-opticalDepth * 0.4)  * phases.y;
			scatteringSun += fastExp(-opticalDepth * 0.15) * phases.z;
			scatteringSun += fastExp(-opticalDepth * 0.05) * phases.w;

		#if 0
			rayLength = 40.0;
			rayStep = vec3(worldDir, 1.0) * rayLength;

			opticalDepth = 0.0;
			// Compute the optical depth of skylight through clouds
			for (uint i = 0u; i < 2u; ++i, worldPos += rayStep.xy) {
				float density = CloudPlaneDensity(worldPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepth += density * rayStep.z;
			}
		#else
			opticalDepth = density * 2e2;
		#endif

		// Compute skylight muti-scattering
		float scatteringSky = fastExp(-opticalDepth * 0.1);
		scatteringSky += 0.2 * fastExp(-opticalDepth * 0.02);

		// Compute powder effect
		float powder = 2.0 * fastExp(-density * 40.0) * oneMinus(fastExp(-density * 80.0));
		// powder = mix(powder, 1.0, sqr(LdotV * 0.5 + 0.5));

		vec3 scattering = scatteringSun * 200.0 * directIlluminance;
		scattering += scatteringSky * 3.0 * skyIlluminance;
		scattering *= oneMinus(0.7 * wetness) * powder * absorption;

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderClouds(in vec3 rayDir, in vec3 skyRadiance, in float dither) {
    vec4 cloudData = vec4(0.0, 0.0, 0.0, 1.0);

    vec3 planeOrigin = vec3(0.0, planetRadius + eyeAltitude, 0.0);
    bool groundIntersection = RaySphereIntersection(planeOrigin, rayDir, planetRadius).y >= 0.0;

	// Compute planar clouds
    if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_PLANE_ALTITUDE)	// Below clouds
     || (groundIntersection && eyeAltitude > CLOUD_PLANE_ALTITUDE)) { // Above clouds
        vec2 cloudIntersection = RaySphereIntersection(planeOrigin, rayDir, planetRadius + CLOUD_PLANE_ALTITUDE);
        float cloudDistance = eyeAltitude > CLOUD_PLANE_ALTITUDE ? cloudIntersection.x : cloudIntersection.y;

        if (cloudDistance > 0.0 && cloudDistance < planetRadius + CLOUD_PLANE_ALTITUDE) {
            vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

            vec4 cloudTemp = vec4(0.0, 0.0, 0.0, 1.0);
            float LdotV = dot(worldLightVector, rayDir);

			// Compute phases for clouds' sunlight multi-scattering
            vec4 phases;    /* Forwards lobe */								 /* Backwards lobe */									  /* Forwards peak */
            phases.x = 	HenyeyGreensteinPhase(LdotV, 0.6) 	  	* 0.7  + HenyeyGreensteinPhase(LdotV, -0.4)		  * 0.25  	  	+ CornetteShanksPhase(LdotV, 0.9) * 0.1;
            phases.y = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.7) * 0.35 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.7) * 0.25 * 0.6 	+ CornetteShanksPhase(LdotV, 0.6) * 0.1 * 0.5;
            phases.z = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.5) * 0.17 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.5) * 0.25 * 0.3 	+ CornetteShanksPhase(LdotV, 0.4) * 0.1 * 0.2;
            phases.w = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.3) * 0.08 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.3) * 0.25 * 0.2 	+ CornetteShanksPhase(LdotV, 0.2) * 0.1 * 0.1;

            vec4 sampleTemp = RenderCloudPlane(cloudDistance * 0.1, cloudPos.xz, rayDir.xz, LdotV, dither, phases);

			// Compute aerial perspective
            if (sampleTemp.a > minCloudAbsorption) {
				vec3 airTransmittance;
				vec3 aerialPerspective = GetSkyRadianceToPoint(atmosphereModel, cloudPos - cameraPosition, worldSunVector, airTransmittance) * 12.0;
				sampleTemp.rgb *= airTransmittance;
				sampleTemp.rgb += aerialPerspective * sampleTemp.a;
            }

            cloudTemp.rgb = sampleTemp.rgb;
            cloudTemp.a -= sampleTemp.a;
            if (eyeAltitude < CLOUD_PLANE_ALTITUDE) {
				// Below clouds
                cloudData.rgb += cloudTemp.rgb * cloudData.a;
            } else {
				// Above clouds
                cloudData.rgb = cloudData.rgb * cloudTemp.a + cloudTemp.rgb;
            }

            cloudData.a *= cloudTemp.a;
        }
    }

	// Remap cloud transmittance
    cloudData.a = remap(minCloudTransmittance, 1.0, cloudData.a);
    return cloudData;
}