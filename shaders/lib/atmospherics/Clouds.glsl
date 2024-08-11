/*
--------------------------------------------------------------------------------

	Referrence: 
		https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn
		http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
		https://odr.chalmers.se/server/api/core/bitstreams/c8634b02-1b52-40c7-a75c-d8c7a9594c2c/content
		https://advances.realtimerendering.com/s2017/Nubis%20-%20Authoring%20Realtime%20Volumetric%20Cloudscapes%20with%20the%20Decima%20Engine%20-%20Final.pptx
		https://advances.realtimerendering.com/s2022/SIGGRAPH2022-Advances-NubisEvolved-NoVideos.pdf

--------------------------------------------------------------------------------
*/


#define CLOUD_CUMULUS 		// Enables cumulus clouds
#define CLOUD_STRATOCUMULUS // Enables stratocumulus clouds
#define CLOUD_CIRROCUMULUS 	// Enables cirrocumulus clouds
#define CLOUD_CIRRUS 		// Enables cirrus clouds

// #define CLOUD_CUMULUS_3D_FBM_WIP // Enables 3D FBM for cumulus clouds (WIP)


#define CLOUD_WIND_SPEED 0.006 // Wind speed of clouds. [0.0 0.0001 0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0]
#define CLOUD_PLANE_ALTITUDE 5500.0 // Altitude of planar clouds. [500.0 600.0 700.0 800.0 900.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 cumulusMaxAltitude 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0]

#define CLOUD_CUMULUS_SAMPLES 		   20 // Sample count for cumulus clouds ray marching. [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 36 40 50 60 100]

#define CLOUD_CUMULUS_SUNLIGHT_SAMPLES 4  // Sample count for sunlight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]
#define CLOUD_CUMULUS_SKYLIGHT_SAMPLES 2  // Sample count for skylight optical depth calculation. [2 3 4 5 6 7 8 9 10 12 15 17 20]

const float cumulusAltitude 	= 1000.0;
const float cumulusThickness 	= 1450.0;
const float cumulusMaxAltitude 	= cumulusAltitude + cumulusThickness;
const float cumulusCoverage 	= 1.1;

const float cumulusExtinction 	= 0.12;
// const float cumulusScattering = 0.12;

const float cirrusExtinction = 0.1;
// const float cirrusScattering = 0.1;

#ifdef CLOUD_CUMULUS_3D_FBM_WIP
	uniform sampler3D depthtex2;
	uniform sampler3D colortex15;
#endif

uniform vec3 cloudWind;

//================================================================================================//

void ToPlanetCurvePos(inout vec3 pos) {
	pos.y += planetRadius;
	pos.y = length(pos); // sqrt(x^2 + y^2 + z^2)
	pos.y -= planetRadius;
}

void FromPlanetCurvePos(inout vec3 pos) {
	pos.y += planetRadius;
	pos.y = sqrt(pos.y * pos.y - pos.x * pos.x - pos.z * pos.z); // sqrt(y^2 - x^2 - z^2)
	pos.y -= planetRadius;
}

// Quadratic polynomial smooth-min function from https://www.iquilezles.org/www/articles/smin/smin.htm
float smin(float a, float b, float k) {
    k *= 4.0;
    float h = max0(k - abs(a - b)) / k;
    return min(a, b) - h * h * k * 0.25;
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

float Calculate3DNoiseSmooth(in vec3 position) {
	vec3 p = floor(position);
	vec3 b = curve(position - p);

	ivec2 texel = ivec2(p.xy + 97.0 * p.z);

	vec2 s0 = texelFetch(noisetex, texel % 256, 0).xy;
	vec2 s1 = texelFetch(noisetex, (texel + ivec2(1, 0)) % 256, 0).xy;
	vec2 s2 = texelFetch(noisetex, (texel + ivec2(0, 1)) % 256, 0).xy;
	vec2 s3 = texelFetch(noisetex, (texel + ivec2(1, 1)) % 256, 0).xy;

	vec2 rg = mix(mix(s0, s1, b.x), mix(s2, s3, b.x), b.y);

	return mix(rg.x, rg.y, b.z);
}

float CloudPlaneDensity(in vec2 rayPos) {
	vec2 shift = cloudWind.xz * CLOUD_WIND_SPEED;

	// Curl noise to simulate wind, makes the positioning of the clouds more natural
	vec2 curl = texture(noisetex, rayPos * 5e-6).xy * 0.04;
	curl += texture(noisetex, rayPos * 1e-5).xy * 0.02;

	float localCoverage = GetSmoothNoise(rayPos * 3e-5 + 2.0 * (curl - shift));
	float density = 0.0;

	#ifdef CLOUD_STRATOCUMULUS
	/* Stratocumulus clouds */ if (localCoverage > 0.3) {
		vec2 position = (rayPos * 6e-4 - shift) * 2e-3;

		float stratocumulus = texture(noisetex, position * 8.5).z, weight = 0.5;

		// Stratocumulus FBM
		for (uint i = 0u; i < 5u; ++i, weight *= 0.47) {
			stratocumulus += weight * texture(noisetex, position).x;
			position = position * 2.8 + (stratocumulus - shift) * 0.016;
		}

		if (stratocumulus > 1e-5) density += sqr(min1(2.4 * max0(stratocumulus - 0.9) * saturate(localCoverage * 1.7 - 0.9)));
	}
	#endif
	#ifdef CLOUD_CIRROCUMULUS
	/* Cirrocumulus clouds */ if (density < 0.1) {
		vec2 position = rayPos * 9e-5 - shift + curl;

		float baseCoverage = curve(texture(noisetex, position * 0.08).z * 0.7 + 0.1);
		baseCoverage *= max0(1.07 - texture(noisetex, position * 0.003).y * 1.4);

		// The base shape of the cirrocumulus clouds using perlin-worley noise
		float cirrocumulus = 0.5 * texture(noisetex, position * vec2(0.4, 0.16)).z;
		cirrocumulus += texture(noisetex, position * 0.9).z - 0.24;
		cirrocumulus = saturate(cirrocumulus - density);

		cirrocumulus *= clamp(baseCoverage - saturate(localCoverage * 1.4 - 0.56), 0.0, 0.25) * 0.64;
		if (cirrocumulus > 1e-6) {
			position.x += cirrocumulus * 0.2;

			// Detail shape of the cirrocumulus clouds
			cirrocumulus += 0.016 * texture(noisetex, position * 3.0).z;
			cirrocumulus += 0.01 * texture(noisetex, position * 5.0 + curl).z - 0.04;

			density += cube(saturate(cirrocumulus * 4.8));
		}
	}
	#endif
	#ifdef CLOUD_CIRRUS
	/* Cirrus clouds */ if (density < 0.1) {
		vec2 position = rayPos * 4e-7 - shift * 4e-3 + curl * 2e-3;
		const vec2 angle = cossin(PI * 0.2);
		const mat2 rot = mat2(angle, -angle.y, angle.x);

		float weight = 0.6;
		float cirrus = texture(noisetex, position).x;

		// Cirrus FBM
		for (uint i = 1u; i < 6u; ++i, weight *= 0.45) {
			position = rot * (position - shift * 4e-3) * vec2(2.7, 2.5 + fastSqrt(i));
			position += cirrus * 4e-3;
			cirrus += texture(noisetex, position).x * weight;
		}
		cirrus -= saturate(localCoverage * 1.65 - 0.6);

		if (cirrus > 1e-5) density += sqr(0.2 * max0(cirrus * 0.9 - 0.77 - density) * cirrus);
	}
	#endif

	return density;
}

float remap(float value, float orignalMin, float orignalMax, float newMin, float newMax) {
    return newMin + (saturate((value - orignalMin) / (orignalMax - orignalMin)) * (newMax - newMin));
}

#ifdef CLOUD_CUMULUS_3D_FBM_WIP
	float CloudVolumeDensity(in vec3 rayPos, in uint octCount) {
		float localCoverage = texture(noisetex, rayPos.xz * 2e-7 - cloudWind.xz * 1e-5).y;
		localCoverage = saturate(fma(localCoverage, 3.0, wetness * 0.55 - 0.55)) * 0.7 + 0.3;
		if (localCoverage < 0.3) return 0.0;

		vec3 shift = CLOUD_WIND_SPEED * cloudWind * 0.4;
		vec3 position = rayPos * 4e-4 - shift;

		vec4 lowFreqNoises = texture(depthtex2, position * 0.16);
		float shape = lowFreqNoises.g * 0.625 + lowFreqNoises.b * 0.25 + lowFreqNoises.a * 0.125;

		shape = remap(lowFreqNoises.x - 1.0, 1.0, shape);

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - cumulusAltitude) * rcp(cumulusThickness));

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 6.0) * oneMinus(saturate((heightFraction - 0.8) * 5.0));

		shape *= gradienShape * cumulusCoverage * localCoverage;
		shape -= heightFraction * 0.22 + 0.64;

		if (shape > 1e-6 && octCount > 3u) {
			vec2 curl = texture(noisetex, position.xz * 0.1).xy;
			position.xy += curl * 4e-2 * oneMinus(heightFraction);

			vec3 worley = texture(colortex15, position * 6.0).rgb;
			float detail = worley.r * 0.625 + worley.g * 0.25 + worley.b * 0.125;
			detail = mix(1.0 - detail, detail, saturate(heightFraction * 10.0));

			shape = remap(detail * 0.06, 1.0, shape);
		}

		return saturate(shape * 4.0);
	}
#else
	float CloudVolumeDensity(in vec3 rayPos, in uint octCount) {
		float localCoverage = texture(noisetex, rayPos.xz * 2e-7 - cloudWind.xz * 1e-5).y;
		localCoverage = saturate(fma(localCoverage, 3.0, wetness * 0.5 - 0.5)) * 0.7 + 0.3;
		if (localCoverage < 0.3) return 0.0;

		//======// FBM cloud shape //=================================================//
		vec3 shift = CLOUD_WIND_SPEED * cloudWind * 0.4;
		vec3 position = rayPos * 4e-4 - shift;

		float density = 0.36 / float(octCount) - 0.76, weight = 1.0;

		for (uint i = 0u; i < octCount; ++i, weight *= 0.5) {
			density += weight * Calculate3DNoise(position);
			position = position * (2.8 + 0.6 * fastSqrt(float(i))) - shift;
		}

		if (density < 1e-6) return 0.0;
		//============================================================================//

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - cumulusAltitude) * rcp(cumulusThickness));

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 6.0) * oneMinus(saturate((heightFraction - 0.8) * 5.0));

		// density = cumulusCoverage == 1.0 ? density : saturate((density - 1.0 + cumulusCoverage) * rcp(cumulusCoverage));

		density *= gradienShape * cumulusCoverage * localCoverage;
		density -= heightFraction * 0.5 + 0.2;

		return saturate(density * 3.2);
	}

	float CloudVolumeDensitySmooth(in vec3 rayPos) {
		float localCoverage = texture(noisetex, rayPos.xz * 2e-7 - cloudWind.xz * 1e-5).y;
		localCoverage = saturate(fma(localCoverage, 3.0, wetness * 0.5 - 0.5)) * 0.7 + 0.3;
		if (localCoverage < 0.3) return 0.0;

		//======// FBM cloud shape //=================================================//
		vec3 shift = CLOUD_WIND_SPEED * cloudWind * 0.4;
		vec3 position = rayPos * 4e-4 - shift;

		float density = 0.36 / 4.0 - 0.76, weight = 1.0;

		for (uint i = 0u; i < 4u; ++i, weight *= 0.5) {
			density += weight * Calculate3DNoise(position);
			position = position * (2.8 + 0.6 * fastSqrt(float(i))) - shift;
		}

		if (density < 1e-6) return 0.0;
		//============================================================================//

		// Remap the height of the clouds to the range of [0, 1]
		float heightFraction = saturate((rayPos.y - cumulusAltitude) * rcp(cumulusThickness));

		// Use two remap functions to carve out the gradient shape
		float gradienShape = saturate(heightFraction * 6.0) * oneMinus(saturate((heightFraction - 0.8) * 5.0));

		// density = cumulusCoverage == 1.0 ? density : saturate((density - 1.0 + cumulusCoverage) * rcp(cumulusCoverage));

		density *= gradienShape * cumulusCoverage * localCoverage;
		density -= heightFraction * 0.5 + 0.2;

		return saturate(density * 3.2);
	}
#endif

#if defined CLOUD_LIGHTING

float CloudVolumeSunlightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = cumulusThickness * (0.2 / float(CLOUD_CUMULUS_SUNLIGHT_SAMPLES));
	vec4 rayStep = vec4(worldLightVector, 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CUMULUS_SUNLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 2.0;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, max(2u, 6u - i));
		if (density < 1e-5) continue;

        // opticalDepth += density * rayStep.w;
        opticalDepth += density;
    }

    return opticalDepth * 8.0;
}

float CloudVolumeSkylightOD(in vec3 rayPos, in float lightNoise) {
    const float stepSize = cumulusThickness * (0.2 / float(CLOUD_CUMULUS_SKYLIGHT_SAMPLES));
	vec4 rayStep = vec4(vec3(0.0, 1.0, 0.0), 1.0) * stepSize;

    float opticalDepth = 0.0;

	for (uint i = 0u; i < CLOUD_CUMULUS_SKYLIGHT_SAMPLES; ++i, rayPos += rayStep.xyz) {
        rayStep *= 2.0;

		float density = CloudVolumeDensity(rayPos + rayStep.xyz * lightNoise, max(2u, 4u - i));
		if (density < 1e-5) continue;

        // opticalDepth += density * rayStep.w;
        opticalDepth += density;
    }

    return opticalDepth * 2.0;
}

vec4 RenderCloudPlane(in float stepT, in vec2 rayPos, in vec2 rayDir, in float LdotV, in float lightNoise, in vec4 phases) {
	float density = CloudPlaneDensity(rayPos);
	if (density > 1e-6) {
		// Siggraph 2017's new formula
		float opticalDepth = density * stepT;
		float absorption = oneMinus(max(fastExp(-opticalDepth), fastExp(-opticalDepth * 0.25) * 0.7));

		float stepSize = 30.0;
		vec2 rayPos = rayPos;
		vec3 rayStep = vec3(worldLightVector.xz, 1.0) * stepSize;
		// float lightNoise = hash1(rayPos);

		opticalDepth = 0.0;
		// Compute the optical depth of sunlight through clouds
		for (uint i = 0u; i < 4u; ++i, rayPos += rayStep.xy) {
			float density = CloudPlaneDensity(rayPos + rayStep.xy * lightNoise);
			if (density < 1e-6) continue;

			rayStep *= 2.0;

			opticalDepth += density * rayStep.z;
		} opticalDepth = smin(opticalDepth, 56.0, 8.0);

		// Compute sunlight multi-scattering
		float scatteringSun =  fastExp(-opticalDepth * 1.0)  * phases.x;
			  scatteringSun += fastExp(-opticalDepth * 0.4)  * phases.y;
			  scatteringSun += fastExp(-opticalDepth * 0.15) * phases.z;
			  scatteringSun += fastExp(-opticalDepth * 0.05) * phases.w;

		#if 0
			stepSize = 40.0;
			rayStep = vec3(rayDir, 1.0) * stepSize;

			opticalDepth = 0.0;
			// Compute the optical depth of skylight through clouds
			for (uint i = 0u; i < 2u; ++i, rayPos += rayStep.xy) {
				float density = CloudPlaneDensity(rayPos + rayStep.xy * lightNoise);
				if (density < 1e-6) continue;

				rayStep *= 2.0;

				opticalDepth += density * rayStep.z;
			}
		#else
			opticalDepth = density * 2e2;
		#endif

		// Compute skylight multi-scattering
		float scatteringSky = fastExp(-opticalDepth * 0.1);
		scatteringSky += 0.2 * fastExp(-opticalDepth * 0.02);

		// Compute powder effect
		// float powder = 2.0 * fastExp(-density * 36.0) * oneMinus(fastExp(-density * 72.0));
		float powder = rcp(fastExp(-density * (TAU / cirrusExtinction)) * 0.7 + 0.3) - 1.0;
		// powder = mix(powder, 0.3, 0.7 * pow1d5(maxEps(LdotV * 0.5 + 0.5)));

		vec3 scattering = scatteringSun * 54.0 * directIlluminance;
		scattering += scatteringSky * 0.2 * (skyIlluminance + lightningShading * 5e-3);
		scattering *= oneMinus(0.6 * wetness) * powder * absorption * rcp(cirrusExtinction);

		return vec4(scattering, absorption);
	}
}

//================================================================================================//

vec4 RenderClouds(in vec3 rayDir/* , in vec3 skyRadiance */, in float dither) {
    vec4 cloudData = vec4(0.0, 0.0, 0.0, 1.0);
	float LdotV = dot(worldLightVector, rayDir);

	// Compute phases for clouds' sunlight multi-scattering
	vec4 phases;    /* Forwards lobe */								 /* Backwards lobe */									  /* Forwards peak */
	phases.x = 	HenyeyGreensteinPhase(LdotV, 0.6) 	  	* 0.7  + HenyeyGreensteinPhase(LdotV, -0.4)		  * 0.25  	  	+ CornetteShanksPhase(LdotV, 0.9) * 0.1;
	phases.y = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.7) * 0.35 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.7) * 0.25 * 0.6 	+ CornetteShanksPhase(LdotV, 0.6) * 0.1 * 0.5;
	phases.z = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.5) * 0.17 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.5) * 0.25 * 0.3 	+ CornetteShanksPhase(LdotV, 0.4) * 0.1 * 0.2;
	phases.w = 	HenyeyGreensteinPhase(LdotV, 0.6 * 0.3) * 0.08 + HenyeyGreensteinPhase(LdotV, -0.4 * 0.3) * 0.25 * 0.2 	+ CornetteShanksPhase(LdotV, 0.2) * 0.1 * 0.1;

	float r = viewerHeight; // length(camera)
	float mu = rayDir.y;	// dot(camera, rayDir) / r

	//================================================================================================//

	// Compute volumetric clouds
	#ifdef CLOUD_CUMULUS
		if ((rayDir.y > 0.0 && eyeAltitude < cumulusAltitude) // Below clouds
		 || (clamp(eyeAltitude, cumulusAltitude, cumulusMaxAltitude) == eyeAltitude) // In clouds
		 || (rayDir.y < 0.0 && eyeAltitude > cumulusMaxAltitude)) { // Above clouds

			// Compute cloud spherical shell intersection
			vec2 intersection = RaySphericalShellIntersection(r, mu, planetRadius + cumulusAltitude, planetRadius + cumulusMaxAltitude);

			if (intersection.y > 0.0) { // Intersect the volume

				// Special treatment for the eye inside the volume
				float isEyeInVolumeSmooth = oneMinus(saturate((eyeAltitude - cumulusMaxAltitude + 5e2) * 2e-3)) * oneMinus(saturate((cumulusAltitude - eyeAltitude + 50.0) * 3e-2));
				float stepLength = max0(mix(intersection.y, min(intersection.y, 2e4), isEyeInVolumeSmooth) - intersection.x);

				#if defined PROGRAM_DEFERRED_0
					uint raySteps = uint(CLOUD_CUMULUS_SAMPLES * 0.6);
				#else
					uint raySteps = CLOUD_CUMULUS_SAMPLES;
					// raySteps = uint(raySteps * min1(0.5 + max0(stepLength - 1e2) * 5e-5)); // Reduce ray steps for vertical rays
					raySteps = uint(raySteps * (isEyeInVolumeSmooth + oneMinus(abs(rayDir) * 0.4))); // Reduce ray steps for vertical rays
				#endif

				// const float nearStepSize = 3.0;
				// const float farStepSizeOffset = 60.0;
				// const float stepAdjustmentDistance = 16384.0;

				// float stepSize = nearStepSize + (farStepSizeOffset / stepAdjustmentDistance) * max0(endLength - startLength);

				float stepSize = stepLength * rcp(float(raySteps));

				vec3 rayStep = stepSize * rayDir;
				ToPlanetCurvePos(rayStep);
				vec3 rayPos = (intersection.x + stepSize * dither) * rayDir + cameraPosition;
				ToPlanetCurvePos(rayPos);

				vec3 rayHitPos = vec3(0.0);
				float rayHitPosWeight = 0.0;

				vec2 stepScattering = vec2(0.0);
				float transmittance = 1.0;

				// float powderFactor = 0.75 * sqr(LdotV * 0.5 + 0.5);

				for (uint i = 0u; i < raySteps; ++i, rayPos += rayStep) {
					if (transmittance < minCloudTransmittance) break;
					if (rayPos.y < cumulusAltitude || rayPos.y > cumulusMaxAltitude) continue;

					float radius = distance(rayPos, cameraPosition);
					if (radius > planetRadius + cumulusMaxAltitude) continue;

					// Compute sample cloud density
					#if defined PROGRAM_DEFERRED_0
						float density = CloudVolumeDensity(rayPos, 4u);
					#else
						float density = CloudVolumeDensity(rayPos, 5u);
					#endif

					if (density < 1e-5) continue;

					rayHitPos += rayPos * transmittance;
					rayHitPosWeight += transmittance;

					#if defined PROGRAM_DEFERRED_0
						vec2 lightNoise = vec2(0.5);
					#else
						// Compute light noise
						vec2 lightNoise = hash2(fract(rayPos)) * 0.5;
					#endif

					// Compute the optical depth of sunlight through clouds
					float opticalDepthSun = CloudVolumeSunlightOD(rayPos, lightNoise.x);

					// Compute sunlight multi-scattering
					float scatteringSun =  fastExp(-opticalDepthSun * 2.0) * phases.x;
						  scatteringSun += fastExp(-opticalDepthSun * 0.8) * phases.y;
						  scatteringSun += fastExp(-opticalDepthSun * 0.3) * phases.z;
						  scatteringSun += fastExp(-opticalDepthSun * 0.1) * phases.w;

					// Compute the optical depth of skylight through clouds
					float opticalDepthSky = CloudVolumeSkylightOD(rayPos, lightNoise.y);
					float scatteringSky = fastExp(-opticalDepthSky) + fastExp(-opticalDepthSky * 0.2) * 0.2;

					// Siggraph 2017's new formula
					float stepOpticalDepth = density * cumulusExtinction * stepSize;
					float stepTransmittance = max(fastExp(-stepOpticalDepth), fastExp(-stepOpticalDepth * 0.25) * 0.7);

					// Compute powder effect
					float powder = rcp(fastExp(-density * (PI / cumulusExtinction)) * 0.85 + 0.15) - 1.0;
					// powder = mix(powder, 1.0, powderFactor);

					// Compute the integral of the scattering over the step
					float stepIntegral = transmittance * oneMinus(stepTransmittance);
					stepScattering += powder * vec2(scatteringSun, scatteringSky) * stepIntegral;
					transmittance *= stepTransmittance;	
				}

				float absorption = 1.0 - transmittance;
				if (absorption > minCloudAbsorption) {
					stepScattering *= oneMinus(0.6 * wetness) * rcp(cumulusExtinction);

					vec3 scattering = stepScattering.x * 3.6 * directIlluminance;
					scattering += stepScattering.y * 0.03 * (skyIlluminance + lightningShading * 5e-3);

					// Compute aerial perspective
					rayHitPos /= rayHitPosWeight;
					FromPlanetCurvePos(rayHitPos);
					rayHitPos -= cameraPosition;
					vec3 airTransmittance;
					vec3 aerialPerspective = GetSkyRadianceToPoint(atmosphereModel, rayHitPos, worldSunVector, airTransmittance) * 12.0;

					scattering *= airTransmittance;
					scattering += aerialPerspective * absorption;

					// Remap cloud transmittance
					transmittance = remap(minCloudTransmittance, 1.0, transmittance);

					cloudData = vec4(scattering, transmittance);
				}
			}
		}
	#endif

	//================================================================================================//

	// Compute planar clouds
	#if defined CLOUD_STRATOCUMULUS || defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
		bool planetIntersection = RayIntersectsGround(r, mu);

		if ((rayDir.y > 0.0 && eyeAltitude < CLOUD_PLANE_ALTITUDE) // Below clouds
		 || (planetIntersection && eyeAltitude > CLOUD_PLANE_ALTITUDE)) { // Above clouds
			vec2 cloudIntersection = RaySphereIntersection(r, mu, planetRadius + CLOUD_PLANE_ALTITUDE);
			float cloudDistance = eyeAltitude > CLOUD_PLANE_ALTITUDE ? cloudIntersection.x : cloudIntersection.y;

			if (cloudDistance > 0.0 && cloudDistance < planetRadius + CLOUD_PLANE_ALTITUDE) {
				vec3 cloudPos = rayDir * cloudDistance + cameraPosition;

				vec4 cloudTemp = vec4(0.0, 0.0, 0.0, 1.0);

				vec4 sampleTemp = RenderCloudPlane(cloudDistance * cirrusExtinction, cloudPos.xz, rayDir.xz, LdotV, dither, phases);

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
	#endif

	// Remap cloud transmittance
    cloudData.a = remap(minCloudTransmittance, 1.0, cloudData.a);
    return cloudData;
}
#endif

//================================================================================================//

#ifdef CLOUD_SHADOWS
float CalculateCloudShadows(in vec3 rayPos) {
    vec3 origin = rayPos + vec3(0.0, planetRadius, 0.0);
    vec2 planePos = RaySphereIntersection(origin, worldLightVector, planetRadius + CLOUD_PLANE_ALTITUDE).y * worldLightVector.xz + rayPos.xz;

	#if defined CLOUD_STRATOCUMULUS || defined CLOUD_CIRROCUMULUS || defined CLOUD_CIRRUS
    	float cloudDensity = CloudPlaneDensity(planePos) * 1e3 * cirrusExtinction;
	#else
    	float cloudDensity = 0.0;
    #endif

	#ifdef CLOUD_CUMULUS
		vec3 cloudPos = RaySphereIntersection(origin, worldLightVector, planetRadius + 0.5 * (cumulusAltitude + cumulusMaxAltitude)).y * worldLightVector + rayPos;
		cloudDensity += CloudVolumeDensitySmooth(cloudPos) * cumulusThickness * cumulusExtinction * 0.1;
	#endif

    // cloudDensity = mix(0.4, cloudDensity, saturate(fastSqrt(abs(worldLightVector.y) * 2.0)));

    return exp2(-0.5 * cloudDensity);
}
#endif