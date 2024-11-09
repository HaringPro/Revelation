#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 screenPos, in vec3 worldDir, in vec3 viewPos) {
	skylight = remap(0.3, 0.7, cube(skylight));

	float NdotV = dot(normal, -worldDir);
    // Unroll the reflect function manually
	vec3 lightDir = worldDir + normal * NdotV * 2.0;

	if (dot(normal, lightDir) < 1e-6) return vec4(0.0);

	vec3 reflection;
	if (skylight > 1e-3) {
		vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

		reflection = skyRadiance * skylight;
	}

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
		edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 3e3;
		reflection += (texelFetch(colortex4, uvToTexel(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade);
	}

	float brdf = FresnelDielectric(NdotV, 0.02);

	return vec4(clamp16f(reflection), brdf);
}

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP && defined PROGRAM_DEFERRED_10
	vec4 CalculateSpecularReflections(Material material, in vec3 normal, in vec3 screenPos, in vec3 worldDir, in vec3 viewPos, in float skylight, in float dither) {
	#ifdef ROUGH_REFLECTIONS
		if (material.isRough) {
			vec3 tangent = normalize(cross(gbufferModelView[1].xyz, normal));
			vec3 bitangent = normalize(cross(normal, tangent));
			mat3 tbnMatrix = mat3(tangent, bitangent, normal);

			vec3 tangentDir = worldDir * tbnMatrix;
			vec3 halfway = tbnMatrix * sampleGGXVNDF(-tangentDir, material.roughness, RandNext2F());

			vec3 lightDir = reflect(worldDir, halfway);

			float NdotL = dot(normal, lightDir);
			if (NdotL < 1e-6) return vec4(0.0);

			bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, uint(RAYTRACE_SAMPLES * oneMinus(material.roughness)), screenPos);

			vec3 reflection;
			if (hit) {
				// reflection = textureLod(colortex4, screenPos.xy * viewPixelSize * 0.5, 8.0 * approxSqrt(material.roughness)).rgb;
				reflection = texelFetch(colortex4, ivec2(screenPos.xy) >> 1, 0).rgb;
			} else if (skylight > 1e-3) {
				vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

				reflection = skyRadiance * skylight;
			}

			vec3 brdf = vec3(1.0);
            float LdotH = dot(lightDir, halfway);

    		// Fresnel term
			if (material.isHardcodedMetal) {
				brdf *= FresnelConductor(LdotH, material.hardcodedMetalCoeff[0], material.hardcodedMetalCoeff[1]);
			} else if (material.metalness > 0.5) {
				brdf *= FresnelSchlick(LdotH, material.f0);
			} else {
				brdf *= FresnelDielectric(LdotH, material.f0);
			}

			// Geometric term
			float NdotV = dot(normal, -worldDir);
			brdf *= saturate(G2SmithGGX(NdotL, NdotV, material.roughness) * G1SmithGGXInverse(NdotV, material.roughness));

			sceneOut *= 1.0 - brdf;

			vec3 reflectViewPos = ScreenToViewSpace(vec3(screenPos.xy * viewPixelSize, loadDepth0(ivec2(screenPos.xy))));
			float targetDepth = saturate(distance(reflectViewPos, viewPos) * rcp(far));

			return vec4(clamp16f(reflection) * brdf, targetDepth);

		} else
	#endif
		{
			float NdotV = dot(normal, -worldDir);
			// Unroll the reflect function manually
			vec3 lightDir = worldDir + normal * NdotV * 2.0;

			if (dot(normal, lightDir) < 1e-6) return vec4(0.0);

			vec3 reflection;
			if (skylight > 1e-3) {
				vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

				reflection = skyRadiance * skylight;
			}

			float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
			bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, RAYTRACE_SAMPLES, screenPos);
			if (hit) {
				screenPos.xy *= viewPixelSize;
				float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
				edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 3e3;
				reflection += (texelFetch(colortex4, uvToTexel(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade);
			}

			vec3 brdf = vec3(1.0);

    		// Fresnel term
			if (material.isHardcodedMetal) {
				brdf *= FresnelConductor(NdotV, material.hardcodedMetalCoeff[0], material.hardcodedMetalCoeff[1]);
			} else if (material.metalness > 0.5) {
				brdf *= FresnelSchlick(NdotV, material.f0);
			} else {
				brdf *= FresnelDielectric(NdotV, material.f0);
			}
			sceneOut *= 1.0 - brdf;

			return vec4(clamp16f(reflection) * brdf, 0.0);
		}
	}
#endif
