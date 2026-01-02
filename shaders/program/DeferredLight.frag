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

/* RENDERTARGETS: 0 */
out vec3 sceneOut;

//======// Uniform //=============================================================================//

writeonly uniform uimage2D colorimg7;

uniform sampler2D cloudOriginTex;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Bruneton08.glsl"
#include "/lib/atmosphere/Celestial.glsl"

#ifdef CLOUD_SHADOWS
	#include "/lib/atmosphere/clouds/Shadows.glsl"
#endif

#include "/lib/lighting/Common.glsl"
#include "/lib/lighting/shadow/Render.glsl"

#if AO_ENABLED > 0 && !defined SSILVB_ENABLED
	#include "/lib/lighting/SSAO.glsl"
	#include "/lib/lighting/GTAO.glsl"
#endif

#include "/lib/SpatialUpscale.glsl"

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

//======// Main //================================================================================//
void main() {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec3 screenPos = vec3(screenCoord, loadDepth0(texelPos));

	#if defined LOD_MOD
		bool lodTerrainMask = screenPos.z > 1.0 - EPS;
		if (lodTerrainMask) {
			screenPos.z = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth0Lod(texelPos)));
		}
	#endif

	// Hand-depth correction
	if (screenPos.z < 0.56) {
		screenPos.z = screenPos.z * rcp(MC_HAND_DEPTH) + (0.5 - 0.5 / MC_HAND_DEPTH);
	}

	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	uvec4 materialPack = loadMaterialPack(texelPos);
	uint materialID = materialPack.y;

	vec3 albedo = sRGBtoLinear(loadAlbedo(texelPos));

	float dither = BlueNoise(texelPos, frameCounter);

	sceneOut = vec3(0.0);

	if (materialID == 0u) { // Sky
		vec3 transmittance;
		sceneOut = GetSkyRadiance(worldDir, worldSunVector, transmittance) * SKY_SPECTRAL_RADIANCE_TO_LUMINANCE;
		sceneOut = colorSaturation(sceneOut, 1.0 - wetness * 0.5); // Post-process

		if (dot(transmittance, vec3(1.0)) > EPS) {
			vec3 celestial = RenderSun(worldDir, worldSunVector);
			vec3 vanillaMoon = albedo;

			#ifdef GALAXY
				celestial += mix(RenderGalaxy(worldDir), vanillaMoon, step(0.06, vanillaMoon.g));
			#else
				celestial += mix(RenderStars(worldDir), vanillaMoon, step(0.06, vanillaMoon.g));
			#endif

			sceneOut += celestial * transmittance;
		}

		#ifdef CLOUDS
			#ifdef CLOUD_TAAU_ENABLED
				vec4 cloudData = texture(cloudReconstructTex, screenCoord);
			#else
				// Dither offset
				screenCoord += viewPixelSize * (dither - 0.5);
				vec4 cloudData = textureBicubic(cloudOriginTex, screenCoord);
			#endif
			sceneOut = sceneOut * cloudData.a + cloudData.rgb;
		#endif

		imageStore(colorimg7, texelPos, uvec4(0));
	} else {
		worldPos += gbufferModelViewInverse[3].xyz;

		vec3 flatNormal, worldNormal;
		FetchNormalData(texelPos, flatNormal, worldNormal);
		vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

		vec2 lightmap = Unpack2x8U(materialPack.x);

		#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
			vec4 specularTex = ExtractSpecularTex(materialPack);

			// Compute rain puddles
			#ifdef RAIN_PUDDLES
				if (wetnessCustom > 1e-2) {
					if (clamp(materialID, 1000u, 1002u) != materialID && materialID != 20u && materialID != 40u) {
						CalculateRainPuddles(albedo, worldNormal, specularTex.rgb, worldPos, flatNormal, lightmap.y);
					}
				}
			#endif

			Material material = GetMaterialData(specularTex);

			materialPack.z = Packup2x8U(specularTex.xy);
			imageStore(colorimg7, texelPos, materialPack);
		#else
			Material material = Material(1.0, 0.0, 0.0, false, false);
		#endif

		float sssAmount = 0.0;
		#if SUBSURFACE_SCATTERING_MODE < 2
			// Hard-coded sss amount for certain materials
			switch (materialID) {
				case 1000u: case 1001u: case 1002u: case 1003u: case 27u: case 28u: // Plants
					sssAmount = 0.6;
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
		sssAmount = linearstep(64.0 * r255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;

		// Cloud shadows
		#ifdef CLOUD_SHADOWS
			// float cloudShadow = CalculateCloudShadows(worldPos);
			vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(worldPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
			float cloudShadow = textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
		#else
			float cloudShadow = 1.0 - wetness * 0.96;
		#endif

		// Sunlight
		vec3 sunlightBase = cloudShadow * saturate(lightmap.y * 1e6 + float(isEyeInWater)) * global.light.directIlluminance;
		vec3 specularDirect = vec3(0.0);

		float worldDistSquared = sdot(worldPos);
		float distanceFade = linearstep(shadowDistance - 8.0, shadowDistance, length(worldPos.xz));
		#if defined LOD_MOD
			distanceFade = saturate(distanceFade + float(lodTerrainMask));
		#endif

		float NdotL = dot(worldNormal, worldLightVector);
		bool doShadows = NdotL > 1e-3;

		// Shadows and SSS
        if (doShadows || sssAmount > 1e-3) {
			vec3 shadow = vec3(1.0);

			// PCSS
        	if (distanceFade < EPS) {
				vec3 normalOffset = flatNormal * (approxSqrt(worldDistSquared) * 2e-3 + 2e-2) * (2.0 - saturate(NdotL));
				shadow = CalculatePCSS(worldPos, normalOffset, dither, sssAmount);
			}

			if (dot(shadow, vec3(1.0)) > EPS) {
			#ifdef SCREEN_SPACE_SHADOWS
				#if defined NORMAL_MAPPING
					vec3 viewFlatNormal = mat3(gbufferModelView) * flatNormal;
				#else
					#define viewFlatNormal viewNormal
				#endif

				float contactShadow = ScreenSpaceShadow(screenPos, viewPos, dither, sssAmount);
			#else
				float contactShadow = float(doShadows);
			#endif

				float LdotV = dot(worldLightVector, -worldDir);

				// Subsurface scattering
				if (sssAmount > 1e-3) {
					float cutout = float(clamp(materialID, 1000u, 1003u) == materialID || clamp(materialID, 27u, 28u) == materialID);
					vec3 sss = mix(shadow, vec3(contactShadow), saturate(distanceFade + cutout * 0.3));

					// Wavelength-dependent approximation
					sss *= pow((albedo + EPS), vec3(cube(saturate(1.0 - mean(sss))) * 2.0 - 0.2)) * sunlightBase;

					float phase = HenyeyGreensteinPhase(-LdotV, 0.7) * 0.25 + uniformPhase * 0.75;
					sceneOut += sss * phase * (2.0 * SUBSURFACE_SCATTERING_BRIGHTNESS);
				}
				if (doShadows) {
					shadow *= contactShadow * sunlightBase;

					// Apply parallax shadows
					#ifdef PARALLAX_SHADOW
						#if defined PARALLAX && !defined PARALLAX_DEPTH_WRITE
							shadow *= oms(loadSceneMain(texelPos).x);
						#endif
					#endif

					vec3 halfway = normalize(worldLightVector - worldDir);
					float NdotV = abs(dot(worldNormal, worldDir));
					float NdotH = dot(worldNormal, halfway);
					float LdotH = dot(worldLightVector, halfway);

					sceneOut += shadow * DiffuseHammon(LdotV, NdotV, NdotL, NdotH, material.roughness, albedo);

					#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
						vec3 f0 = GetMaterialF0(material.metalness, albedo);
					#else
						const vec3 f0 = vec3(DEFAULT_DIELECTRIC_F0);
					#endif

					specularDirect = shadow * SphericalAreaGGX(LdotH, NdotV, NdotL, LdotV, material.roughness, f0);
				}
			}
		}

		// Ambient occlusion
		#if AO_ENABLED > 0 && !defined SSILVB_ENABLED
			vec3 ao = vec3(1.0);
			#if AO_ENABLED == 1
				ao.x = CalculateSSAO(screenCoord, viewPos, viewNormal, SampleStbnUnitvec2(texelPos, frameCounter));
			#else
				ao.x = CalculateGTAO(screenCoord, viewPos, viewNormal, SampleStbnVec2(texelPos, frameCounter));
			#endif

			#ifdef AO_MULTI_BOUNCE
				ao = ApproxMultiBounce(ao.x, albedo);
			#else
				ao = vec3(ao.x);
			#endif
		#else
			const float ao = 1.0;
		#endif

		// Skylight and bounced sunlight
		#ifndef SSILVB_ENABLED
			if (lightmap.y > EPS) {
				// Spherical harmonics skylight
				vec3 skylight = ConvolvedReconstructSH3(global.light.skySH, worldNormal);
				sceneOut += skylight * cube(lightmap.y) * ao;

				// Fake bounced light
				float bounce = CalculateFakeBouncedLight(worldNormal);
				sceneOut += bounce * pow5(lightmap.y) * sunlightBase * ao;
			}
		#endif

		// Emissive & Blocklight
		vec3 blocklightColor = blackbody(float(BLOCKLIGHT_TEMPERATURE));
		#if EMISSIVE_MODE > 0 && defined SPECULAR_MAPPING
			sceneOut += material.emissiveness * dot(albedo, vec3(0.75));
		#endif
		#if EMISSIVE_MODE < 2
			// Hard-coded emissive
			vec4 emissive = HardCodeEmissive(materialID, albedo, worldPos, blocklightColor);
			#ifndef SSILVB_ENABLED
				if (emissive.a * lightmap.x > EPS) {
					lightmap.x = CalculateBlocklightFalloff(lightmap.x);
					sceneOut += lightmap.x * emissive.a * (ao * oms(lightmap.x) + lightmap.x) * blocklightColor;
				}
			#endif

			sceneOut += emissive.rgb * EMISSIVE_BRIGHTNESS;
		#elif !defined SSILVB_ENABLED
			lightmap.x = CalculateBlocklightFalloff(lightmap.x);
			sceneOut += lightmap.x * (ao * oms(lightmap.x) + lightmap.x) * blocklightColor;
		#endif

		// Handheld light
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > EPS) {
				float NdotL = saturate(dot(worldNormal, -worldDir));
				float attenuation = rcp(1.0 + worldDistSquared) * NdotL;
				float irradiance = max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS;

				sceneOut += irradiance * attenuation * blocklightColor;
			}
		#endif

		// Lightning
		sceneOut += LightningContribution(worldPos, worldNormal);

		// Indirect diffuse lighting
		#ifdef SSILVB_ENABLED
			#ifdef SVGF_ENABLED
				float NdotV = abs(dot(worldNormal, worldDir));
				sceneOut += YCoCgToSRGB(SpatialUpscale(texelPos >> 1, worldNormal, length(viewPos), NdotV));
			#else
				sceneOut += YCoCgToSRGB(texelFetch(colortex3, texelPos >> 1, 0).rgb);
			#endif
		#endif

		// Minimal ambient light
		sceneOut += (worldNormal.y * 0.4 + 0.6) * max(MINIMUM_AMBIENT_BRIGHTNESS, 5e-3 * nightVision) * ao;

		// Apply albedo (for diffuse)
		sceneOut *= albedo;

		// Metallic diffuse elimination
		material.metalness *= 0.2 * lightmap.y + 0.8;
		sceneOut *= oms(material.metalness);

		// Direct specular lighting
		sceneOut += specularDirect;

		// Output clamp
		sceneOut = satU16f(sceneOut);
	}
}
