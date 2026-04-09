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
layout (location = 0) out vec4 sceneOut;

//======// Uniform //=============================================================================//

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

#include "/lib/atmosphere/Rainbow.glsl"
#include "/lib/atmosphere/CommonFog.glsl"

#include "/lib/SpatialUpscale.glsl"

#include "/lib/water/WaterFog.glsl"

#include "/lib/surface/BRDF.glsl"
#include "/lib/surface/SSRT.glsl"

vec2 CalculateRefractedCoord(in ivec2 texelPos, in vec3 viewPos, in vec3 screenPos, in bool waterMask) {
	vec3 viewNormal = mat3(gbufferModelView) * FetchSurfaceNormal(texelPos);
	float viewLengthInv = inversesqrt(sdot(viewPos));
	vec3 viewDir = viewPos * viewLengthInv;

	vec3 refractedDir;
	if (waterMask) {
		vec3 viewGeometryNormal = mat3(gbufferModelView) * FetchGeometryNormal(texelPos);
		refractedDir = refract(viewDir, viewNormal - viewGeometryNormal * 0.95, 1.0 / WATER_IOR);
	} else {
		refractedDir = refract(viewDir, viewNormal, 1.0 / GLASS_IOR);
	}

	#ifdef RAYTRACED_REFRACTION
		float dither = BlueNoise(texelPos, frameCounter);
		vec3 rayPos = screenPos;

		if (!ScreenSpaceRaytrace(viewPos, refractedDir, dither, 16, rayPos)) return screenPos.xy;

		vec2 refractedCoord = rayPos.xy;
	#else
		// Estimate refraction depth
		float depth1 = loadDepth1(texelPos);
		vec3 viewPos1 = ScreenToViewPos(vec3(screenPos.xy, depth1));
		#if defined LOD_MOD
			if (depth1 > 1.0 - EPS) {
				depth1 = loadDepth1Lod(texelPos);
				viewPos1 = ScreenToViewPosLod(vec3(screenPos.xy, depth1));
			}
		#endif

		refractedDir *= min(distance(viewPos, viewPos1) * viewLengthInv, 4.0);
		refractedDir *= mix(0.125, 4.0, waterMask) * REFRACTION_STRENGTH;

		vec2 refractedCoord = ViewToScreenPos(viewPos + refractedDir).xy;
	#endif

	float refractedDepth = loadDepth1(uvToTexel(refractedCoord));
	refractedCoord = mix(refractedCoord, screenPos.xy, step(refractedDepth, screenPos.z));

	vec2 edgeFade = smoothstep(0.8, 1.0, abs(refractedCoord * 2.0 - 1.0));
	return mix(refractedCoord, screenPos.xy, edgeFade);
}

//======// Main //================================================================================//
void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	float depth = loadDepth0(texelPos);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewPos(screenPos);
	#if defined LOD_MOD
		if (depth > 1.0 - EPS) {
			depth = screenPos.z = loadDepth0Lod(texelPos);
			viewPos = ScreenToViewPosLod(screenPos);
		}
	#endif

	#if defined LOD_MOD
    	float screenDepthSky = ViewToScreenDepth(ScreenToViewDepthLod(1.0));
	#else
    	#define screenDepthSky 1.0
	#endif

	uvec4 materialPack = loadMaterialPack(texelPos);

	uint materialID = materialPack.y;
	bool glassMask = materialID == 2u;
	bool waterMask = materialID == 3u;

	// Process refraction
	ivec2 refractedTexel = texelPos;
	if (glassMask || waterMask) {
		refractedTexel = uvToTexel(CalculateRefractedCoord(texelPos, viewPos, screenPos, waterMask));
	}

    vec3 sceneColor = loadSceneMain(refractedTexel);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	if (depth < screenDepthSky) {
		vec4 translucent = ExtractSpecularTex(materialPack);
		vec3 albedo = sRGBToLinear(translucent.rgb);

		// Particle translucent
		if (materialID == 500u) {
			vec3 diffuseLight = texelFetch(colortex3, texelPos, 0).rgb;
			sceneColor = mix(sceneColor, albedo * diffuseLight, translucent.a);
		}

		// Translucent
		if (glassMask || waterMask) {
			if (glassMask) {
				// Absorption
				sceneColor *= exp2(log2(albedo) * approxSqrt(translucent.a));

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

				vec3 skyRadiance = AtmosphereSkyView(atmosphereViewPos, worldDir, worldSunDir);
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

	float viewDistance = length(viewPos);
	float LdotV = dot(worldLightDir, worldDir);

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 waterFog = UpscaleVolumetricFog(texelPos, -viewPos.z);
		#else
			mat2x3 waterFog = AnalyticWaterFog(eyeSkylightSmooth, viewDistance, LdotV);
		#endif
		sceneColor = ApplyFog(sceneColor, waterFog);
		fogMask = mean(waterFog[1]);
	}

	// Vanilla fog
	RenderVanillaFog(sceneColor, fogMask, viewDistance);

	// Convert to YCoCg for TAA clipping
	#if defined TAA_ENABLED && RENDER_MODE == 1
		sceneColor = RGBToYCoCg(sceneColor);
	#endif

	#if DEBUG_NORMALS == 1
		sceneColor = FetchSurfaceNormal(texelPos) * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneColor = FetchGeometryNormal(texelPos) * 0.5 + 0.5;
	#endif

	sceneOut = vec4(sceneColor, saturate(1.0 - fogMask));
}