/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Compute direct lighting, combine with indirect lighting and atmosphere

--------------------------------------------------------------------------------
*/

#define PASS_COMBINE_LIGHTING

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
out vec3 sceneOut;

//======// Uniform //=============================================================================//

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
#include "/lib/atmosphere/Celestial.glsl"

#include "/lib/atmosphere/clouds/Render.glsl"
#include "/lib/atmosphere/clouds/Shadows.glsl"

#include "/lib/lighting/Common.glsl"
#include "/lib/lighting/shadow/Render.glsl"

#if AO_ENABLED > 0 && !defined SSILVB_ENABLED
	#include "/lib/lighting/SSAO.glsl"
	#include "/lib/lighting/GTAO.glsl"
#endif

#if defined SSILVB_ENABLED && defined SVGF_ENABLED
	vec3 UpscaleDiffuseIndirect(vec2 coord, vec3 worldNormal, float viewDistance, float NdotV) {
		vec3 sum = vec3(0.0);
		float sumWeight = 0.0;

		float sigmaZ = -4.0 * NdotV;

		ivec2 texelEnd = ivec2(halfViewEnd) - 1;
		coord = coord * viewSize * 0.5 - 0.5;

		ivec2 floorTexel = ivec2(floor(coord));
		vec2 fractTexel = coord - vec2(floorTexel);

		float bilinearWeight[4] = {
			oms(fractTexel.x) * oms(fractTexel.y),
			fractTexel.x      * oms(fractTexel.y),
			oms(fractTexel.x) * fractTexel.y,
			fractTexel.x      * fractTexel.y
		};

		for (uint i = 0u; i < 4u; ++i) {
			ivec2 sampleTexel = clamp(floorTexel + offset2x2[i], ivec2(1), texelEnd);

			vec3 sampleAux = texelFetch(colortex14, sampleTexel, 0).rgb;

			float weight = pow4(saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal)));
			weight *= exp2(distance(sampleAux.z, viewDistance) * sigmaZ);
			weight *= bilinearWeight[i];

			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

			sum += sampleLight * weight;
			sumWeight += weight;
		}

		if (sumWeight < EPS) return vec3(0.0);

		return sum * rcp(sumWeight);
	}
#endif

//======// Main //================================================================================//
void main() {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	uvec4 materialPack = loadMaterialPack(texelPos);
	uint materialID = materialPack.y;

	vec3 albedo = FetchBaseColor(texelPos);

	float dither = BlueNoise(texelPos, frameCounter);

	sceneOut = vec3(0.0);

	if (materialID == 0u) { // Sky
		vec3 viewDir  = ScreenToViewDir(screenCoord);
		vec3 worldDir = mat3(gbufferModelViewInverse) * viewDir;

		vec3 transmittance = AtmosphereTransmittance(atmosphereViewPos, worldDir);
		vec3 skyRadiance = AtmosphereSkyView(atmosphereViewPos, worldDir, worldSunDir);

		sceneOut = skyRadiance;

		// Clouds
		#ifdef CLOUDS
			#ifdef CLOUD_TAAU_ENABLED
				vec4 cloudData = texture(cloudReconstructTex, screenCoord);
			#else
				// Dither offset
				screenCoord += viewPixelSize * (dither - 0.5);
				vec4 cloudData = textureBicubic(cloudOriginTex, screenCoord);
			#endif

			CompositeClouds(sceneOut, cloudData, worldDir);
			transmittance *= cloudData.w;
		#endif

		// Celestial objects
		if (dot(transmittance, vec3(1.0)) > EPS) {
			vec3 celestial = RenderSun(worldDir, worldSunDir);

			#ifdef RENDER_MOON
				vec4 moon = RenderMoon(worldDir, worldMoonDir);
			#else
				vec4 moon = vec4(albedo, step(0.06, albedo.g));
			#endif

			#ifdef GALAXY
				celestial += mix(RenderGalaxy(worldDir), moon.rgb, moon.a);
			#else
				celestial += mix(RenderStars(worldDir), moon.rgb, moon.a);
			#endif

			sceneOut += celestial * transmittance;
		}
	} else {
		vec3 screenPos = vec3(screenCoord, loadDepth0(texelPos));

		#if defined LOD_MOD
			bool lodMask = screenPos.z > 1.0 - EPS;
			if (lodMask) {
				screenPos.z = ViewToScreenDepth(ScreenToViewDepthLod(loadDepth0Lod(texelPos)));
			}
		#endif

		// Hand-depth correction
		if (screenPos.z < 0.56) {
			screenPos.z = screenPos.z * rcp(MC_HAND_DEPTH) + (0.5 - 0.5 / MC_HAND_DEPTH);
		}

		vec3 viewPos = ScreenToViewPos(screenPos);
		float viewDist = length(viewPos);

		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
		vec3 worldDir = worldPos / viewDist;
		worldPos += gbufferModelViewInverse[3].xyz;

		vec3 geoNormal, worldNormal;
		FetchNormalData(texelPos, geoNormal, worldNormal);
		vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

		vec2 lightmap = Unpack2x8U(materialPack.x);
		vec4 specularTex = ExtractSpecularTex(materialPack);

		Material material = GetMaterialData(specularTex);

		#if defined MC_SPECULAR_MAP
			vec3 f0 = GetMaterialF0(material.metalness, albedo);
		#else
			const vec3 f0 = vec3(DEFAULT_DIELECTRIC_F0);
		#endif

		float sssAmount = 0.0;
		#if SUBSURFACE_SCATTERING_MODE < 2
			// Hard-coded sss amount for certain materials
			switch (materialID) {
				case 1000u: case 1001u: case 1002u: case 1003u: case 27u: case 28u: // Plants
					sssAmount = 0.6;
					break;
				case 13u: // Leaves
					sssAmount = 0.8;
					break;
				case 37u: case 39u: // Weak SSS
					sssAmount = 0.5;
					break;
				case 38u: case 51u: // Strong SSS
					sssAmount = 0.8;
					break;
				case 40u: // Particles
					sssAmount = 0.3;
					break;
			}
		#endif
		#if TEXTURE_FORMAT == 0 && SUBSURFACE_SCATTERING_MODE > 0 && defined MC_SPECULAR_MAP
			sssAmount = max(sssAmount, specularTex.b * step(64.5 * rcp255, specularTex.b));
		#endif

		// Remap sss amount to [0, 1] range
		sssAmount = linearstep(64.0 * rcp255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;

		vec3 diffuseRadiance = vec3(0.0);
		vec3 specularRadiance = vec3(0.0);

		// Cloud shadows
		#ifdef CLOUD_SHADOWS
			// float cloudShadow = CalculateCloudShadows(worldPos);
			vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(worldPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
			float cloudShadow = textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
		#else
			float cloudShadow = 1.0 - wetness * 0.96;
		#endif

		// Sunlight
		vec3 sunlightBase = cloudShadow * saturate(lightmap.y * 1e6 + float(isEyeInWater)) * global.directIlluminance;

		float distanceFade = linearstep(shadowDistance - 8.0, shadowDistance, length(viewPos.xz));
		#if defined LOD_MOD
			distanceFade = saturate(distanceFade + float(lodMask));
		#endif

		float NdotL = saturate(dot(worldNormal, worldLightDir));
		float NdotV = abs(dot(worldNormal, worldDir));

		// Shadows and SSS
		if (NdotL + sssAmount > EPS) {
			vec3 shadow = vec3(saturate(NdotL * FLT_MAX));
			float surfaceDepth = 0.0;

			float normalOffsetBase = (viewDist * 2e-3 + 2e-2) * (2.0 - NdotL);

			// PCSS
			if (distanceFade < EPS) {
				shadow *= CalculatePCSS(worldPos, geoNormal * normalOffsetBase, dither, surfaceDepth);
			}

			#ifdef SCREEN_SPACE_SHADOWS
				float contactShadow = ScreenSpaceShadow(screenPos, viewPos + viewNormal * normalOffsetBase, dither, sssAmount);
			#else
				const float contactShadow = 1.0;
			#endif

			float LdotV = dot(worldLightDir, worldDir);

			// Subsurface scattering
			if (sssAmount > EPS) {
				vec3 beta = approxSqrt(saturate(normalize(albedo)));
				vec3 sigmaA = oms(beta) * 16.0 / (sssAmount * SUBSURFACE_SCATTERING_STRENGTH);
				vec3 sigmaS = 4.0 * beta * sssAmount;

				float phase = HenyeyGreensteinPhase(LdotV, 0.7) * 0.25 + uniformPhase * 0.75;
				vec3 sss = sigmaS * phase * exp2(-rLOG2 * surfaceDepth * (sigmaS + sigmaA));

				float cutout = step(maxOf(abs(geoNormal)), 0.99);
				sss *= mix(1.0, contactShadow, saturate(distanceFade + cutout * 0.75));

				diffuseRadiance += sunlightBase * sss * SUBSURFACE_SCATTERING_BRIGHTNESS;
			}
			if (dot(shadow, vec3(1.0)) > EPS) {
				shadow *= contactShadow * sunlightBase;

				// Apply parallax shadows
				#ifdef PARALLAX_SHADOW
					#if defined PARALLAX && !defined PARALLAX_DEPTH_WRITE
						shadow *= oms(texelFetch(colortex12, texelPos, 0).x);
					#endif
				#endif

				vec3 halfway = normalize(worldLightDir - worldDir);
				float NdotH = saturate(dot(worldNormal, halfway));
				float LdotH = saturate(dot(worldLightDir, halfway));
				float VdotH = saturate(-dot(worldDir, halfway));

				diffuseRadiance += shadow * DiffuseHammon(NdotV, NdotL, VdotH, NdotH, material.roughness, albedo) * NdotL;
				specularRadiance += shadow * SpecularGGX(LdotH, NdotV, NdotL, NdotH, material.roughness, f0) * NdotL;
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

		// Skylight & Blocklight
		#ifndef SSILVB_ENABLED
			if (lightmap.y > EPS) {
				// Spherical harmonics skylight
				vec3 skylight = ConvolvedReconstructSH3(global.skySH, worldNormal);
				diffuseRadiance += skylight * cube(lightmap.y) * ao;

				// Fake bounced light
				float bounce = CalculateFakeBouncedLight(worldNormal);
				diffuseRadiance += bounce * pow5(lightmap.y) * sunlightBase * ao;
			}

			if (lightmap.x > EPS) {
				lightmap.x = CalculateBlocklightFalloff(lightmap.x);
				diffuseRadiance += lightmap.x * (ao * oms(lightmap.x) + lightmap.x) * blocklightColor;
			}
		#endif

		// Emissive
		#if EMISSIVE_MODE > 0 && defined MC_SPECULAR_MAP
			diffuseRadiance += material.emissiveness * 4.0 * sdot(albedo);
		#endif
		#if EMISSIVE_MODE < 2
			// Hard-coded emissive
			diffuseRadiance += HardCodeEmissive(materialID, albedo, worldPos) * EMISSIVE_BRIGHTNESS;
		#endif

		// Handheld light
		#ifdef HANDHELD_LIGHTING
			if (heldBlockLightValue + heldBlockLightValue2 > EPS) {
				float NdotL = saturate(dot(worldNormal, -worldDir));
				float attenuation = rcp(1.0 + viewDist * viewDist) * NdotL;
				float irradiance = max(heldBlockLightValue, heldBlockLightValue2) * HELD_LIGHT_BRIGHTNESS;

				diffuseRadiance += irradiance * attenuation * blocklightColor;
			}
		#endif

		// Lightning
		diffuseRadiance += LightningContribution(worldPos, worldNormal);

		// Indirect diffuse lighting
		#ifdef SSILVB_ENABLED
			#ifdef SVGF_ENABLED
				vec3 radiance = UpscaleDiffuseIndirect(screenCoord, worldNormal, viewDist, NdotV);
			#else
				vec3 radiance = texelFetch(colortex3, texelPos >> 1, 0).rgb;
			#endif
			diffuseRadiance += YCoCgToRGB(radiance);
		#endif

		// Minimal ambient light
		diffuseRadiance += (worldNormal.y * 0.4 + 0.6) * max(MINIMUM_AMBIENT_BRIGHTNESS, 5e-3 * nightVision) * ao;

		// Apply diffuse color (baseColor * (1 - metallic))
		material.metalness *= 0.2 * lightmap.y + 0.8;
		diffuseRadiance *= albedo * oms(material.metalness);

		// Indirect specular
		if (material.specularMask) {
			vec2 brdf = texture(brdfLutTex, vec2(material.roughness, NdotV)).xy;

			vec3 specular = f0 * brdf.x + brdf.y;
			specularRadiance += loadSceneMain(texelPos) * specular;
		}

		sceneOut = diffuseRadiance + specularRadiance;
	}
}
