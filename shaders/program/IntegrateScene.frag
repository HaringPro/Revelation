/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Compute refraction, combine translucent and fog

--------------------------------------------------------------------------------
*/

#define PASS_COMPOSITE

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 sceneOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"

#include "/lib/atmosphere/Rainbow.glsl"
#include "/lib/atmosphere/VanillaFog.glsl"

#include "/lib/water/WaterFog.glsl"

#include "/lib/surface/Material.glsl"

#include "/lib/lighting/BRDF.glsl"
#include "/lib/lighting/SSRT.glsl"

void CalculateTranslucentRefraction(inout vec3 sceneColor, ivec2 texelPos, vec3 viewPos, vec3 screenPos, bool waterMask) {
	vec3 viewNormal = mat3(gbufferModelView) * FetchSurfaceNormal(texelPos);
	vec3 viewDir = normalize(viewPos);

    float eta = waterMask ? (isEyeInWater == 1 ? WATER_IOR : 1.0 / WATER_IOR) : 1.0 / GLASS_IOR;
	vec3 refractedDir = refract(viewDir, viewNormal, eta);

	#ifdef RAYTRACED_REFRACTION
		float dither = BlueNoise(texelPos, frameCounter);
		vec3 rayPos = screenPos;

		if (!ScreenSpaceRaytrace(viewPos, refractedDir, dither, REFRACTION_SAMPLES, rayPos)) {
            return;
        }

		vec2 refractedCoord = rayPos.xy;
	#else
        // Newton's method for refraction
        // https://jcgt.org/published/0015/01/03/
        vec3 viewPosBack = ScreenToViewPos(vec3(screenPos.xy, loadDepth1(texelPos)));
		vec2 refractedCoord = screenPos.xy;

        for (uint i = 0u; i < REFRACTION_SAMPLES; ++i) {
            float denom = dot(viewNormal, refractedDir);
            if (abs(denom) < EPS) break;

            float t = dot(viewPosBack - viewPos, viewNormal) / denom;
            vec3 hitViewPos = viewPos + refractedDir * t;

            vec3 hitScreenPos = ViewToScreenPos(hitViewPos);
            ivec2 hitTexelPos = uvToTexelScaled(hitScreenPos.xy);

            vec3 screenPosBack = vec3(hitScreenPos.xy, loadDepth1(hitTexelPos));
            viewPosBack = ScreenToViewPos(screenPosBack);
            viewNormal = mat3(gbufferModelView) * FetchGeometryNormal(hitTexelPos);

            if (sdot(hitViewPos - viewPosBack) < 1.0) {
                refractedCoord = hitScreenPos.xy;
                break;
            }
        }
	#endif

	float refractedDepth = loadDepth1(uvToTexelScaled(refractedCoord));
	refractedCoord = mix(refractedCoord, screenPos.xy, step(refractedDepth, screenPos.z));

    ivec2 refractedTexel = uvToTexelScaled(refractedCoord);
	float confidence = smoothstep(0.8, 1.0, maxOf(abs(refractedCoord * 2.0 - 1.0)));
    sceneColor = mix(loadSceneMain(refractedTexel), sceneColor, confidence);

    // Skybox reflection for occluded water
    if (!waterMask && isEyeInWater == 0) {
	    vec2 waterData = texelFetch(colortex12, refractedTexel, 0).xy;
        if (waterData.x > 0.0) {
            vec3 worldNormal = OctDecodeUnorm(Unpack2x8(waterData.y));

            vec3 worldDir = mat3(gbufferModelViewInverse) * ScreenToViewDir(refractedCoord);

            float NdotV = abs(dot(worldNormal, worldDir));
            vec3 rayDir = worldDir + worldNormal * NdotV * 2.0;

            vec2 skyViewCoord = ProjectCubemap(rayDir, 96.0);
            vec3 skyRadiance = textureBicubic(skyEnvMapTex, skyViewCoord).rgb;

            vec2 lightmap = Unpack2x8U(loadMaterialPack(refractedTexel).x);

            vec3 reflection = skyRadiance * smoothstep(0.3, 0.7, lightmap.y);
            float fresnel = FresnelDielectricN(NdotV, WATER_IOR);

            sceneColor = mix(sceneColor, reflection, fresnel);
        }
    }
}

#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	mat2x3 UnpackFogData(uvec2 data) {
		return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
	}

	mat2x3 UpscaleVolumetricFog(ivec2 texelPos, float linearDepth) {
		ivec2 randTexel = ivec2(vec2(texelPos >> 1) + BlueNoise(texelPos, frameCounter + 7));
		float sigmaZ = -32.0 / linearDepth;

		mat2x3 sum = UnpackFogData(texelFetch(colortex11, randTexel, 0).xy);
		float sumWeight = 1.0;

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = randTexel + offset3x3N[i];
			uvec3 sampleFogData = texelFetch(colortex11, sampleTexel, 0).xyz;

			float sampleDepth = uintBitsToFloat(sampleFogData.z);
			float weight = exp2(abs(sampleDepth - linearDepth) * sigmaZ);

			sum += UnpackFogData(sampleFogData.xy) * weight;
			sumWeight += weight;
		}

		sum *= rcp(sumWeight);
		return sum;
	}
#endif

//======// Main //================================================================================//
void main() {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * scaledTexelSize;

	float depth = loadDepth0(texelPos);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewPos(screenPos);

	uvec4 materialPack = loadMaterialPack(texelPos);

	uint materialID = materialPack.y;
	bool glassMask = materialID == 2u;
	bool waterMask = materialID == 3u;

	vec3 sceneColor = loadSceneMain(texelPos);

	// Process refraction
	if (glassMask || waterMask) {
        CalculateTranslucentRefraction(sceneColor, texelPos, viewPos, screenPos, waterMask);
	}

	#if defined LOD_MOD
		if (depth > 1.0 - EPS) {
			depth = screenPos.z = loadDepth0Lod(texelPos);
			viewPos = ScreenToViewPosLod(screenPos);
		}
	#endif

	float viewDist = length(viewPos);
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = worldPos / viewDist;
	worldPos += gbufferModelViewInverse[3].xyz;

	if (lessThanFLT1(depth)) {
		vec4 translucentColor = loadAlbedo(texelPos);
		vec3 albedo = sRGBToLinear(translucentColor.rgb) * sRGB_2_Rec2020;

		// Particle translucent
		if (materialID == 500u) {
			vec3 diffuseLight = texelFetch(colortex3, texelPos, 0).rgb;
			sceneColor = mix(sceneColor, albedo * diffuseLight, translucentColor.a);
		}

		// Translucent
		if (glassMask || waterMask) {
			if (glassMask) {
				// Absorption
				sceneColor *= exp2(log2(albedo * oms(0.125 * translucentColor.a)) * approxSqrt(translucentColor.a + 0.25));

				// Emissive
				sceneColor += (2.0 * EMISSIVE_BRIGHTNESS) * Unpack2x8UX(materialPack.x) * mean(albedo) * albedo;
			}

			// Apply specular lighting
			vec4 specularLight = texelFetch(colortex3, texelPos, 0);
			sceneColor = sceneColor * specularLight.a + specularLight.rgb;
		}

		// Border fog
		#ifdef BORDER_FOG
			if (isEyeInWater == 0) {
				float density = exp2(-0.1 * max0(worldPos.y - 63.0)) * pow8(sdot(worldPos.xz) * rcp(lodRenderDist * lodRenderDist));
				float transmittance = exp2(-BORDER_FOG_FALLOFF * density);

				vec3 skyRadiance = AtmosphereSkyView(atmosphereViewPos, worldDir, sunDirWorld);
				sceneColor = mix(skyRadiance, sceneColor, transmittance);
			}
		#endif
	}

	// Initialize
	float fogMask = 1.0;

	// Volumetric fog
	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			mat2x3 volFogData = UpscaleVolumetricFog(texelPos, -viewPos.z);
			sceneColor = ApplyFog(sceneColor, volFogData);
			fogMask = mix(1.0, mean(volFogData[1]), eyeSkylightSmooth);
		}
	#endif

	float LdotV = dot(shadowDirWorld, worldDir);

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 waterFog = UpscaleVolumetricFog(texelPos, -viewPos.z);
		#else
			mat2x3 waterFog = AnalyticWaterFog(eyeSkylightSmooth, viewDist, LdotV);
		#endif
		sceneColor = ApplyFog(sceneColor, waterFog);
		fogMask = mean(waterFog[1]);
	}

	// Vanilla fog
	RenderVanillaFog(sceneColor, fogMask, viewDist);

	#if DEBUG_NORMALS == 1
		sceneColor = FetchSurfaceNormal(texelPos) * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneColor = FetchGeometryNormal(texelPos) * 0.5 + 0.5;
	#endif

	// Convert to YCoCg for TAA clipping
	#if defined TAA_ENABLED && RENDER_MODE == 1
		sceneColor = RGBToYCoCg(sceneColor);
	#endif

	sceneOut = vec4(sceneColor, saturate(1.0 - fogMask));
}
