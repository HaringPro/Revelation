
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,3,4 */
layout (location = 0) out vec4 sceneOut;
layout (location = 1) out vec4 gbufferOut0;
layout (location = 2) out vec4 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#include "/lib/utility/Uniform.inc"

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 minecraftPos;
in vec4 viewPos;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Noise.inc"

#include "/lib/atmospherics/Global.inc"

#include "/lib/water/WaterWave.glsl"
// #include "/lib/water/WaterFog.glsl"

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 viewPos) {
	skylight = smoothstep(0.3, 0.8, cube(skylight));
	vec3 viewDir = normalize(viewPos);
	normal = mat3(gbufferModelView) * normal;

	float LdotH = dot(normal, -viewDir);
	vec3 rayDir = viewDir + normal * LdotH * 2.0;

	float NdotL = dot(normal, rayDir);
	if (NdotL < 1e-6) return vec4(0.0);

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z);

	vec3 reflection;
	if (skylight > 1e-3) {
		if (isEyeInWater == 0) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld)).rgb;

			reflection = skyRadiance * skylight;
		} else /* if (materialID == 3u)  */{
			reflection = skyIlluminance * 5e-3 / (vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B) + 1e-2);
		}
	}

	float NdotV = max(1e-6, dot(normal, -viewDir));
	bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		vec2 previousCoord = Reproject(screenPos).xy;
		if (saturate(previousCoord) == previousCoord) {
			float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
			reflection += (texelFetch(colortex7, rawCoord(previousCoord), 0).rgb - reflection) * saturate(edgeFade * 7e2);
		}
	}

	float brdf;
	if (isEyeInWater == 1) { // Total internal reflection
		//specular = FresnelDielectricN(NdotV, 1.000293 / WATER_REFRACT_IOR);
		brdf = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
	} else {
		brdf = FresnelDielectricN(NdotV, /* materialID == 3u ? WATER_REFRACT_IOR : GLASS_REFRACT_IOR */WATER_REFRACT_IOR);
	}

	return vec4(reflection * brdf, brdf);
}

//======// Main //================================================================================//
void main() {
	vec3 normalOut;
	vec4 albedo;
	if (materialID == 3u) { // water
		#ifdef WATER_PARALLAX
			normalOut = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y, normalize(minecraftPos - cameraPosition) * tbnMatrix);
		#else
			normalOut = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
		#endif

		gbufferOut1.x = packUnorm2x8(normalOut.xy * 0.5 + 0.5);
		// albedo = sceneOut = vec4(0.0, 0.0, 0.0, 1e-2);

		normalOut = normalize(tbnMatrix * normalOut);
		sceneOut = CalculateSpecularReflections(normalOut, lightmap.y, viewPos.xyz);
	} else {
		albedo = texture(tex, texCoord) * tint;

		if (albedo.a < 0.1) { discard; return; }

		sceneOut = vec4(vec3(0.0), albedo.a);
		normalOut = tbnMatrix[2];
	}

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos.xyz;
	vec3 worldDir = normalize(worldPos);
	worldPos += gbufferModelViewInverse[3].xyz;

	float LdotV = dot(worldLightVector, -worldDir);
	float NdotL = dot(normalOut, worldLightVector);

	// Sunlight
	vec3 sunlightMult = fma(wetness, -15.5, 16.0) * directIlluminance;

	vec3 shadow = vec3(0.0);
	float diffuseBRDF = fastSqrt(NdotL) * rPI;
	float specularBRDF = 0.0;

	float distortFactor;
	vec3 normalOffset = normalOut * fma(dotSelf(worldPos), 4e-5, 2e-2) * (2.0 - saturate(NdotL));

	vec3 shadowProjPos = WorldPosToShadowProjPosBias(worldPos + normalOffset, distortFactor);	

	// float distanceFade = saturate(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

	#ifdef TAA_ENABLED
		float dither = BlueNoiseTemporal();
	#else
		float dither = InterleavedGradientNoise(gl_FragCoord.xy);
	#endif

	// Shadows
	if (NdotL > 1e-3) {
		vec2 blockerSearch = BlockerSearch(shadowProjPos, dither);
		float penumbraScale = max(blockerSearch.x / distortFactor, 2.0 / realShadowMapRes);
		shadow = PercentageCloserFilter(shadowProjPos, dither, penumbraScale);

		if (maxOf(shadow) > 1e-6) {
			float NdotV = saturate(dot(normalOut, -worldDir));
			float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
			float NdotH = (NdotL + NdotV) * halfwayNorm;
			float LdotH = LdotV * halfwayNorm + halfwayNorm;

			// diffuseBRDF *= DiffuseHammon(LdotV, max(NdotV, 1e-3), NdotL, NdotH, 0.01, albedo.rgb);

			specularBRDF = 2.0 * SpecularBRDF(LdotH, max(NdotV, 1e-3), NdotL, NdotH, sqr(0.01), 0.04);

			shadow *= saturate(lightmap.y * 1e8);
			shadow *= sunlightMult;
		}
	}

	if (materialID != 3u) {
		gbufferOut1.x = packUnorm2x8(albedo.rg);
		gbufferOut1.y = packUnorm2x8(albedo.ba);

		sceneOut.rgb += shadow * diffuseBRDF;

		if (lightmap.y > 1e-5) {
			// Skylight
			vec3 skylight = skyIlluminance * 0.75;
			skylight = mix(skylight, directIlluminance * 0.05, wetness * 0.5 + 0.2);
			skylight *= normalOut.y * 1.2 + 1.8;

			sceneOut.rgb += skylight * cube(lightmap.y);

			// Bounced light
			float bounce = CalculateFittedBouncedLight(normalOut);
			bounce *= pow5(lightmap.y);
			sceneOut.rgb += bounce * sunlightMult;
		}

		if (lightmap.x > 1e-5) sceneOut.rgb += CalculateBlocklightFalloff(lightmap.x) * blackbody(float(BLOCKLIGHT_TEMPERATURE));
		// if (materialID != 3u) {
		// 	sceneOut.rgb *= albedo.rgb;
		// 	// sceneOut.rgb += (reflections.rgb - sceneOut.rgb) * reflections.a;
		// }
		// albedo.a = sqrt2(albedo.a);
		// shadow /= cube(1.0 - albedo.a + saturate(albedo.rgb * albedo.a) * albedo.a);
	}

	// Specular highlights
	sceneOut.rgb += shadow * specularBRDF;
	sceneOut.rgb /= maxEps(sceneOut.a);

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(normalOut));
	gbufferOut0.w = gbufferOut0.z;
}