#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 screenPos, in vec3 worldDir, in vec3 viewPos) {
	skylight = remap(0.3, 0.7, cube(skylight));

	float NdotV = abs(dot(normal, worldDir));
    // Unroll the reflect function manually
	vec3 lightDir = worldDir + normal * NdotV * 2.0;

	if (dot(normal, lightDir) < EPS) return vec4(0.0);

	vec3 reflection;
	if (skylight > 1e-3) {
		vec3 skyRadiance = textureBicubic(skyViewTex, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

		reflection = skyRadiance * skylight;
	}

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oms(screenPos.x) * oms(screenPos.y);
		edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 3e3;
		reflection += (texelFetch(colortex4, uvToTexel(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade);
	}

	float fresnel = FresnelDielectric(NdotV, 0.02);
	return vec4(satU16f(reflection), fresnel);
}

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP && defined PASS_DEFERRED_LIGHTING
	vec4 CalculateSpecularReflections(Material material, in vec3 normal, in vec3 screenPos, in vec3 worldDir, in vec3 viewPos, in float skylight, in float dither) {
	#ifdef ROUGH_REFLECTIONS
		if (material.isRough) {
    		NoiseGenerator noiseGenerator = initNoiseGenerator(uvec2(gl_FragCoord.xy), uint(frameCounter));
			vec3 halfway = SampleGGXVNDF(nextVec2(noiseGenerator), -worldDir, material.roughness, normal);

			vec3 lightDir = reflect(worldDir, halfway);

			float NdotL = dot(normal, lightDir);
			if (NdotL < EPS) return vec4(0.0);

			bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, uint(RAYTRACE_SAMPLES * oms(material.roughness)), screenPos);

			vec3 reflection;
			if (hit) {
				// reflection = textureLod(colortex4, screenPos.xy * viewPixelSize * 0.5, 8.0 * approxSqrt(material.roughness)).rgb;
				reflection = texelFetch(colortex4, ivec2(screenPos.xy) >> 1, 0).rgb;
			} else if (skylight > 1e-3) {
				vec3 skyRadiance = textureBicubic(skyViewTex, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

				reflection = skyRadiance * skylight;
			}
            // float LdotH = dot(lightDir, halfway);
			// float NdotV = abs(dot(normal, worldDir));

			vec3 reflectViewPos = ScreenToViewSpace(vec3(screenPos.xy * viewPixelSize, loadDepth0(ivec2(screenPos.xy))));
			return vec4(satU16f(reflection), distance(reflectViewPos, viewPos));
		} else
	#endif
		{
			float NdotV = abs(dot(normal, worldDir));
			// Unroll the reflect function manually
			vec3 lightDir = worldDir + normal * NdotV * 2.0;

			float NdotL = dot(normal, lightDir);
			if (NdotL < EPS) return vec4(0.0);

			vec3 reflection;
			if (skylight > 1e-3) {
				vec3 skyRadiance = textureBicubic(skyViewTex, FromSkyViewLutParams(lightDir) + vec2(0.0, 0.5)).rgb;

				reflection = skyRadiance * skylight;
			}

			bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, RAYTRACE_SAMPLES, screenPos);
			if (hit) {
				screenPos.xy *= viewPixelSize;
				float edgeFade = screenPos.x * screenPos.y * oms(screenPos.x) * oms(screenPos.y);
				edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 3e3;
				reflection += (texelFetch(colortex4, uvToTexel(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade);
			}

			return vec4(satU16f(reflection), 0.0);
		}
	}
#endif
