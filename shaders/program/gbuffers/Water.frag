
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,7,8 */
layout (location = 0) out vec4 sceneOut;
layout (location = 1) out vec4 gbufferOut0;
layout (location = 2) out vec2 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

#include "/lib/universal/Uniform.glsl"

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 worldPos;
in vec3 viewPos;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"

#include "/lib/atmospherics/Global.glsl"

#define PHYSICS_OCEAN_SUPPORT

#ifdef PHYSICS_OCEAN
	#define PHYSICS_FRAGMENT
	#include "/lib/water/PhysicsOceans.glsl"
#else
	#include "/lib/water/WaterWave.glsl"
#endif
// #include "/lib/water/WaterFog.glsl"

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 worldDir) {
	skylight = remap(0.3, 0.7, cube(skylight));

	float NdotV = dot(normal, -worldDir);
    // Unroll the reflect function manually
	vec3 rayDir = worldDir + normal * NdotV * 2.0;

	if (dot(normal, rayDir) < 1e-6) return vec4(0.0);

	float f0 = materialID == 3u ? F0FromIOR(WATER_REFRACT_IOR) : F0FromIOR(GLASS_REFRACT_IOR);
	float brdf;

    // Fresnel term
	if (isEyeInWater == 1) {
		// Total internal reflection
		// brdf = FresnelDielectricN(NdotV, 1.000293 / WATER_REFRACT_IOR);
		brdf = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
	} else {
		brdf = FresnelDielectric(NdotV, f0);
	}

	vec3 reflection;
	if (skylight > 1e-3 && (isEyeInWater == 0 || materialID != 3u)) {
		vec2 skyViewCoord = FromSkyViewLutParams(rayDir) + vec2(0.0, 0.5);
		vec3 skyRadiance = textureBicubic(colortex5, skyViewCoord).rgb;

		reflection = skyRadiance * skylight * brdf;

		#ifndef TRANSLUCENT_LIGHTING
			// Specular highlights
			float NdotL = dot(normal, worldLightVector);

			if (NdotL > 1e-3) {
				float LdotV = dot(worldLightVector, -worldDir);
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = (NdotL + NdotV) * halfwayNorm;
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				vec3 transmittance = textureBicubic(colortex10, skyViewCoord).rgb * (oneMinus(wetness * 0.96) * 1e2 * skylight);
				reflection += transmittance * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(TRANSLUCENT_ROUGHNESS), f0);
			}
		#endif
	}

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z);

	bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
		edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 4e3;
		reflection += (texelFetch(colortex4, rawCoord(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade) * brdf;
	}

	return vec4(reflection, brdf);
}

//======// Main //================================================================================//
void main() {
	vec3 worldNormal;
	vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

	if (materialID == 3u) { // water
		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			worldNormal = wave.normal;
			gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
		#else
			vec3 minecraftPos = worldPos + cameraPosition;
			#ifdef WATER_PARALLAX
				worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y, normalize(worldPos - gbufferModelViewInverse[3].xyz) * tbnMatrix);
			#else
				worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
			#endif

			gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
			worldNormal = tbnMatrix * worldNormal;
		#endif

		// Water normal clamp
		worldNormal = normalize(worldNormal + tbnMatrix[2] * inversesqrt(maxEps(dot(tbnMatrix[2], -worldDir))));
		sceneOut = CalculateSpecularReflections(worldNormal, lightmap.y, worldDir);
	} else {
		vec4 albedo = texture(tex, texCoord) * tint;

		if (albedo.a < 0.1) { discard; return; }

		#if defined NORMAL_MAPPING
			worldNormal = texture(normals, texCoord).rgb;
			DecodeNormalTex(worldNormal);

			worldNormal = tbnMatrix * worldNormal;
			gbufferOut0.w = packUnorm2x8(encodeUnitVector(worldNormal));
		#else
			worldNormal = tbnMatrix[2];
		#endif

		#ifdef TRANSLUCENT_LIGHTING
			sceneOut.rgb = albedo.rgb;
			sceneOut.a = albedo.a * TRANSLUCENT_LIGHTING_BLENDED_FACTOR;
		#else
			sceneOut = CalculateSpecularReflections(worldNormal, lightmap.y, worldDir);
		#endif

		gbufferOut1.x = packUnorm2x8(albedo.rg);
		gbufferOut1.y = packUnorm2x8(albedo.ba);
	}

	//==// Translucent lighting //================================================================//
	#ifdef TRANSLUCENT_LIGHTING
		// Sunlight
		vec3 sunlightMult = 16.0 * oneMinus(wetness * 0.96) * directIlluminance;
		float NdotL = dot(worldNormal, worldLightVector);

		vec3 sunlightDiffuse = vec3(0.0);
		vec3 specularHighlight = vec3(0.0);

		// float distanceFade = sqr(pow16(0.64 * rcp(shadowDistance * shadowDistance) * dotSelf(worldPos.xz)));

		// Shadows
		if (NdotL > 1e-3) {
			float distortFactor;
			float worldDistSquared = dotSelf(worldPos);

			vec3 normalOffset = tbnMatrix[2] * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
			vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortFactor);	

			if (saturate(shadowScreenPos) == shadowScreenPos) {
				float dither = BlueNoiseTemporal(ivec2(gl_FragCoord.xy));

				float blockerSearch = BlockerSearch(shadowScreenPos, dither);
				float penumbraScale = max(blockerSearch / distortFactor, 2.0 / realShadowMapRes);
				shadowScreenPos.z -= (worldDistSquared * 1e-9 + 3e-6) * (1.0 + dither) * distortFactor * shadowDistance;

				vec3 shadow = PercentageCloserFilter(shadowScreenPos, dither, penumbraScale) * saturate(lightmap.y * 1e8);

				if (dot(shadow, vec3(1.0)) > 1e-6) {
					float LdotV = dot(worldLightVector, -worldDir);
					float NdotV = saturate(dot(worldNormal, -worldDir));
					float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
					float NdotH = (NdotL + NdotV) * halfwayNorm;
					float LdotH = LdotV * halfwayNorm + halfwayNorm;

					shadow *= sunlightMult;

					sunlightDiffuse = shadow * approxSqrt(NdotL) * rPI;
					float f0 = materialID == 3u ? F0FromIOR(WATER_REFRACT_IOR) : F0FromIOR(GLASS_REFRACT_IOR);
					specularHighlight = shadow * 4.0 * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(TRANSLUCENT_ROUGHNESS), f0);
				}
			}
		}

		if (materialID != 3u) {
			vec3 lighting = sunlightDiffuse;

			if (lightmap.y > 1e-5) {
				// Skylight
				vec3 skylight = skyIlluminance * 0.75;
				skylight = mix(skylight, directIlluminance * 0.05, wetness * 0.5 + 0.2);
				skylight *= worldNormal.y * 1.2 + 1.8;

				lighting += skylight * cube(lightmap.y);

				// Bounced light
				float bounce = CalculateApproxBouncedLight(worldNormal);
				bounce *= pow5(lightmap.y);
				lighting += bounce * sunlightMult;
			}

			if (lightmap.x > 1e-5) lighting += CalculateBlocklightFalloff(lightmap.x) * blackbody(float(BLOCKLIGHT_TEMPERATURE));
			sceneOut.rgb *= lighting;

			vec4 specularReflections = CalculateSpecularReflections(worldNormal, lightmap.y, viewPos);
			sceneOut.rgb = specularReflections.rgb + sceneOut.rgb * oneMinus(specularReflections.a);
		}

		// Specular highlights
		sceneOut.rgb += specularHighlight;
	#endif

	//============================================================================================//

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID) * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(tbnMatrix[2]));
}