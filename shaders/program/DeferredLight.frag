/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Deferred lighting and sky combination
		  Compute specular reflections

--------------------------------------------------------------------------------
*/

#define PASS_DEFERRED_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,1 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out vec4 reflectionOut;

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 0,1,8 */
layout (location = 2) out vec2 specularOut;
#endif

//======// Uniform //=============================================================================//

uniform sampler3D atmosCombinedLut;

#include "/lib/universal/Uniform.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Offset.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Global.glsl"
#include "/lib/atmosphere/PrecomputedAtmosphericScattering.glsl"
#include "/lib/atmosphere/Celestial.glsl"

#ifdef AURORA
	#include "/lib/atmosphere/Aurora.glsl"
#endif

#ifdef CLOUD_SHADOWS
	#include "/lib/atmosphere/clouds/Shadows.glsl"
#endif

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#if AO_ENABLED > 0 && !defined SSPT_ENABLED
	#include "/lib/lighting/SSAO.glsl"
	#include "/lib/lighting/GTAO.glsl"
#endif

#include "/lib/SpatialUpscale.glsl"

#include "/lib/surface/Reflection.glsl"

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec3 screenPos = vec3(screenCoord, loadDepth0(screenTexel));
	vec3 viewPos = ScreenToViewSpace(screenPos);

	#if defined DISTANT_HORIZONS
		bool dhTerrainMask = screenPos.z > 0.999999;
		if (dhTerrainMask) {
			screenPos.z = loadDepth0DH(screenTexel);
			viewPos = ScreenToViewSpaceDH(screenPos);
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	uvec4 gbufferData0 = loadGbufferData0(screenTexel);

	uint materialID = gbufferData0.y;

	vec3 albedoRaw = loadAlbedo(screenTexel);
	vec3 albedo = sRGBtoLinear(albedoRaw);

	float dither = BlueNoiseTemporal(screenTexel);

	sceneOut = vec3(0.0);

	if (screenPos.z > 0.999999 + float(materialID)) {
		vec2 skyViewCoord = FromSkyViewLutParams(worldDir);
		sceneOut = textureBicubic(colortex5, skyViewCoord).rgb;

		if (!RayIntersectsGround(viewerHeight, worldDir.y)) {
			vec3 celestial = RenderSun(worldDir, worldSunVector);
			vec3 moonDisc = mix(albedo, luminance(albedo) * vec3(0.7, 1.1, 1.5), 0.5) * 0.1;
			#ifdef GALAXY
				celestial += mix(RenderGalaxy(worldDir), moonDisc, bvec3(albedo.g > 0.06)); // Use bvec3 to avoid errors with some drivers
			#else
				celestial += mix(RenderStars(worldDir), moonDisc, bvec3(albedo.g > 0.06)); // Use bvec3 to avoid errors with some drivers
			#endif

			vec3 transmittance = GetTransmittanceToTopAtmosphereBoundary(viewerHeight, worldDir.y);
			sceneOut += celestial * mix(vec3(1.0), transmittance, step(viewerHeight, atmosphereModel.top_radius));
		}

		#ifdef CLOUDS
			// Dither offset
			screenCoord += viewPixelSize * (dither * 2.0 - 1.0);

			#ifdef CLOUD_CBR_ENABLED
				vec4 cloudData = textureBicubic(colortex9, screenCoord);
			#else
				vec4 cloudData = textureBicubic(colortex2, screenCoord);
			#endif
			sceneOut = sceneOut * cloudData.a + cloudData.rgb;
		#endif
	} else {
		worldPos += gbufferModelViewInverse[3].xyz;

		vec3 flatNormal = FetchFlatNormal(gbufferData0);
		#ifdef NORMAL_MAPPING
			vec3 worldNormal = FetchWorldNormal(gbufferData0);
		#else
			vec3 worldNormal = flatNormal;
		#endif
		vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

		vec2 lightmap = Unpack2x8U(gbufferData0.x);
		lightmap.y = saturate(lightmap.y + float(isEyeInWater));

		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			vec2 specularData = loadGbufferData1(screenTexel).xy;
			vec4 specularTex = vec4(Unpack2x8(specularData.x), Unpack2x8(specularData.y));

			// Compute rain puddles
			#ifdef RAIN_PUDDLES
				if (wetnessCustom > 1e-2) {
					if (clamp(materialID, 9u, 12u) != materialID && materialID != 20u && materialID != 40u) {
						CalculateRainPuddles(albedo, worldNormal, specularTex.rgb, worldPos, flatNormal, lightmap.y);
					}
				}
			#endif

			Material material = GetMaterialData(specularTex);
			specularOut = specularTex.rg;
		#else
			Material material = Material(materialID == 46u || materialID == 51u ? 0.005 : 1.0, 0.0, DEFAULT_DIELECTRIC_F0, 0.0, false, false);
		#endif

		float sssAmount = 0.0;
		#if SUBSURFACE_SCATTERING_MODE < 2
			// Hard-coded sss amount for certain materials
			switch (materialID) {
				case 9u: case 10u: case 11u: case 12u: case 27u: case 28u: // Plants
					sssAmount = 0.5;
					break;
				case 13u: // Leaves
					sssAmount = 0.85;
					break;
				case 37u: case 39u: // Weak SSS
					sssAmount = 0.5;
					break;
				case 38u: case 51u: // Strong SSS
					sssAmount = 0.8;
					break;
				case 40u: // Particles
					sssAmount = 0.35;
					break;
			}
		#endif
		#if TEXTURE_FORMAT == 0 && SUBSURFACE_SCATTERING_MODE > 0 && defined SPECULAR_MAPPING
			sssAmount = max(sssAmount, specularTex.b * step(64.5 * r255, specularTex.b));
		#endif

		// Remap sss amount to [0, 1] range
		sssAmount = remap(64.0 * r255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;

		// Ambient occlusion
		#if AO_ENABLED > 0 && !defined SSPT_ENABLED
			vec3 ao = vec3(1.0);
			if (screenPos.z > 0.56) {
			#if defined DISTANT_HORIZONS
				if (dhTerrainMask) {
				#if AO_ENABLED == 1
					ao.x = CalculateSSAODH(screenCoord, viewPos, viewNormal, dither);
				#else
					ao.x = CalculateGTAODH(screenCoord, viewPos, viewNormal, dither);
				#endif
				} else
			#endif
				{
				#if AO_ENABLED == 1
					ao.x = CalculateSSAO(screenCoord, viewPos, viewNormal, dither);
				#else
					ao.x = CalculateGTAO(screenCoord, viewPos, viewNormal, dither);
				#endif
				}

				#ifdef AO_MULTI_BOUNCE
					ao = ApproxMultiBounce(ao.x, albedo);
				#endif
			}
		#else
			const float ao = 1.0;
		#endif

		// Cloud shadows
		#ifdef CLOUD_SHADOWS
			// float cloudShadow = CalculateCloudShadows(worldPos);
			vec2 cloudShadowCoord = WorldToCloudShadowPos(worldPos) + (dither * 2.0 - 1.0) / textureSize(colortex10, 0);
			float cloudShadow = textureBicubic(colortex10, saturate(cloudShadowCoord)).x;
		#else
			float cloudShadow = 1.0 - wetness * 0.96;
		#endif

		// Sunlight
		vec3 sunlightMult = cloudShadow * loadDirectIllum();
		vec3 specularHighlight = vec3(0.0);

		float worldDistSquared = sdot(worldPos);
		float distanceFade = sqr(pow16(0.64 * rcp(shadowDistance * shadowDistance) * sdot(worldPos.xz)));
		#if defined DISTANT_HORIZONS
			distanceFade = saturate(distanceFade + float(dhTerrainMask));
		#endif

		float LdotV = dot(worldLightVector, -worldDir);
		float NdotL = dot(worldNormal, worldLightVector);

		bool doShadows = NdotL > 1e-3;
		bool doSss = sssAmount > 1e-3;
		bool inShadowMapRange = distanceFade < EPS;

		// Shadows and SSS
        if (doShadows || doSss) {
			vec3 shadow = sunlightMult;

			// Apply shadowmap
        	if (inShadowMapRange) {
				float distortionFactor;
				vec3 normalOffset = flatNormal * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
				vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortionFactor);	

				if (saturate(shadowScreenPos) == shadowScreenPos) {
					vec2 blockerSearch;
					// Sub-surface scattering
					if (doSss) {
						blockerSearch = BlockerSearchSSS(shadowScreenPos, dither, 0.25 * (1.0 + sssAmount) * distortionFactor);
						vec3 subsurfaceScattering = CalculateSubsurfaceScattering(albedo, sssAmount, blockerSearch.y, LdotV);

						// Formula from https://www.alanzucconi.com/2017/08/30/fast-subsurface-scattering-1/
						// float bssrdf = sqr(saturate(dot(worldDir, worldLightVector + 0.2 * worldNormal))) * 4.0;
						sceneOut += subsurfaceScattering * sunlightMult * ao;
					} else {
						blockerSearch.x = BlockerSearch(shadowScreenPos, dither, 0.25 * distortionFactor);
					}

					// Shadows
					if (doShadows) {
						shadowScreenPos.z -= (worldDistSquared * 1e-9 + 3e-6) * (1.0 + dither) / distortionFactor * shadowDistance;

						shadow *= PercentageCloserFilter(shadowScreenPos, worldPos, dither, 0.5 * blockerSearch.x * distortionFactor) * saturate(lightmap.y * 1e8);
					}
				}
			}

			// Process diffuse and specular highlights
			if (doShadows && dot(shadow, vec3(1.0)) > EPS || doSss && !inShadowMapRange) {
				#ifdef SCREEN_SPACE_SHADOWS
					#if defined NORMAL_MAPPING
						vec3 viewFlatNormal = mat3(gbufferModelView) * flatNormal;
					#else
						#define viewFlatNormal viewNormal
					#endif

				#if defined DISTANT_HORIZONS
					if (dhTerrainMask)
						shadow *= materialID == 39u ? 1.0 : ScreenSpaceShadowDH(viewPos, screenPos, viewFlatNormal, dither, sssAmount);
					else
				#endif
						shadow *= materialID == 39u ? 1.0 : ScreenSpaceShadow(viewPos, screenPos, viewFlatNormal, dither, sssAmount);
				#endif

				// Apply parallax shadows
				#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
					shadow *= oms(loadGbufferData1(screenTexel).z);
				#endif

				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotV = abs(dot(worldNormal, -worldDir));
				float NdotH = saturate((NdotL + NdotV) * halfwayNorm);
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				// Sunlight diffuse
				vec3 sunlightDiffuse = DiffuseHammon(LdotV, NdotV, NdotL, NdotH, material.roughness, albedo);
				sunlightDiffuse += PI * SUBSURFACE_SCATTERING_BRIGHTNESS * uniformPhase * sssAmount * distanceFade;
				sceneOut += shadow * saturate(sunlightDiffuse);

				specularHighlight = shadow * SpecularBRDF(LdotH, NdotV, saturate(NdotL), NdotH, material.roughness, material.f0);
				specularHighlight *= oms(material.metalness * oms(albedo));
			}
		}

		// Skylight and bounced sunlight
		#ifndef SSPT_ENABLED
			if (lightmap.y > 1e-5) {
				// Skylight
				vec3 skylight = lightningShading;
				#ifdef AURORA
					skylight += 0.2 * auroraShading;
				#endif
				skylight *= 1e-3 * (worldNormal.y * 0.5 + 0.5);

				// Spherical harmonics skylight
				vec3[4] skySH;
				for (uint band = 0u; band < 4u; ++band) {
					skySH[band] = texelFetch(colortex4, ivec2(int(viewWidth) - 1, band + 2), 0).rgb;
				}
				skylight += max(FromSphericalHarmonics(skySH, worldNormal), skySH[0] * 0.2820947918);

				sceneOut += skylight * cube(lightmap.y) * ao;

			#ifndef RSM_ENABLED
				// Bounced sunlight
				float bounce = CalculateApproxBouncedLight(worldNormal);
				bounce *= pow5(lightmap.y);
				sceneOut += bounce * sunlightMult * ao;
			#endif
			}
		#endif

		// Emissive & Blocklight
		vec3 blocklightColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
		#if EMISSIVE_MODE > 0 && defined SPECULAR_MAPPING
			sceneOut += material.emissiveness * dot(albedo, vec3(0.75));
		#endif
		#if EMISSIVE_MODE < 2
			// Hard-coded emissive
			vec4 emissive = HardCodeEmissive(materialID, albedo, albedoRaw, worldPos, blocklightColor);
			#ifndef SSPT_ENABLED
				if (emissive.a * lightmap.x > 1e-5) {
					lightmap.x = CalculateBlocklightFalloff(lightmap.x);
					sceneOut += lightmap.x * (ao * oms(lightmap.x) + lightmap.x) * blocklightColor * emissive.a;
				}
			#endif

			sceneOut += emissive.rgb * EMISSIVE_BRIGHTNESS;
		#elif !defined SSPT_ENABLED
			lightmap.x = CalculateBlocklightFalloff(lightmap.x);
			sceneOut += lightmap.x * (ao * oms(lightmap.x) + lightmap.x) * blocklightColor;
		#endif

		// Handheld light
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > 1e-4) {
				float NdotL = saturate(dot(worldNormal, -worldDir)) * 0.8 + 0.2;
				float attenuation = rcp(1.0 + worldDistSquared) * NdotL;
				float irradiance = attenuation * max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS;

				sceneOut += irradiance * (ao - oms(ao) * sqr(attenuation)) * blocklightColor;
			}
		#endif

		// Specular reflections
		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			if (material.hasReflections && materialID != 46u && materialID != 51u) {
				lightmap.y = remap(0.3, 0.7, lightmap.y);

				reflectionOut = CalculateSpecularReflections(material, worldNormal, screenPos, worldDir, viewPos, lightmap.y, dither);

				// Metallic diffuse elimination
				material.metalness *= 0.2 * lightmap.y + 0.8;
				albedo *= oms(material.metalness);
			} else
		#endif
		// Clear buffer
		reflectionOut = vec4(0.0);

		// Global illumination
		#ifdef SSPT_ENABLED
			#ifdef SVGF_ENABLED
				float NdotV = abs(dot(worldNormal, worldDir));
				sceneOut += SpatialUpscale5x5(screenTexel >> 1, worldNormal, length(viewPos), NdotV);
			#else
				sceneOut += texelFetch(colortex3, screenTexel >> 1, 0), 0).rgb;
			#endif
		#elif defined RSM_ENABLED
			float NdotV = abs(dot(worldNormal, worldDir));
			vec3 rsm = SpatialUpscale5x5(screenTexel >> 1, worldNormal, length(viewPos), NdotV);
			sceneOut += rsm * ao * sunlightMult;
		#endif

		// Minimal ambient light
		sceneOut += vec3(0.77, 0.82, 1.0) * ((worldNormal.y * 0.4 + 0.6) * MINIMUM_AMBIENT_BRIGHTNESS) * ao;

		// Apply albedo
		sceneOut *= albedo;

		// Specular highlights
		sceneOut += specularHighlight;

		// Output clamp
		sceneOut = satU16f(sceneOut);
	}
}