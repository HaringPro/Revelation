#include "/lib/lighting/SSRT.glsl"
#include "/lib/universal/MonteCarlo.glsl"

vec4 CalculateSpecularReflections(Material material, vec3 worldNormal, vec3 screenPos, vec3 worldDir, vec3 viewPos, float skylight, float dither) {
	viewPos += mat3(gbufferModelView) * worldNormal * saturate(length(viewPos) * 3e-4);

	vec3 halfway = worldNormal;
#ifdef ROUGH_REFLECTIONS
	if (!material.mirrorMask) {
		mat3 tbnMatrix = BuildOrthonormalBasis(worldNormal);

		vec2 noise = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter + 3);
		halfway = tbnMatrix * SampleVisibleGGX(-worldDir * tbnMatrix, material.roughness, noise);
	}
#endif
	vec3 lightDir = reflect(worldDir, halfway);

	float NdotL = dot(worldNormal, lightDir);
	if (NdotL < EPS) return vec4(0.0);

	vec4 reflection = vec4(0.0, 0.0, 0.0, FP16_MAX);
	if (skylight > EPS && isEyeInWater == 0) {
		vec3 skyRadiance = textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(lightDir, 96.0))).rgb;
		reflection.rgb = skyRadiance * smoothstep(0.3, 0.7, skylight);
	}

	uint stepCount = uint(SSRT_MAX_SAMPLES * oms(material.roughness * 0.75));
	if (ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, stepCount, screenPos)) {
		float edgeFade = screenPos.x * screenPos.y * oms(screenPos.x) * oms(screenPos.y);
		edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 1e3;
		reflection.rgb += (texture(colortex4, screenPos.xy).rgb - reflection.rgb) * saturate(edgeFade);

		ivec2 texel = uvToTexelScaled(screenPos.xy);
		vec3 reflectViewPos = ScreenToViewPos(vec3(screenPos.xy, loadDepth0(texel)));
		reflection.a = distance(reflectViewPos, viewPos);
	}

	return reflection;
}
