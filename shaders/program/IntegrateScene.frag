/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Compute refraction, combine translucent, reflections and fog

--------------------------------------------------------------------------------
*/

#define PASS_COMPOSITE

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,12 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogMask;

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
#include "/lib/atmosphere/Bruneton08.glsl"

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
		vec3 viewPos1 = ScreenToViewSpace(vec3(screenPos.xy, depth1));
		#if defined LOD_MOD
			if (depth1 > 1.0 - EPS) {
				depth1 = loadDepth1Lod(texelPos);
				viewPos1 = ScreenToViewSpaceLod(vec3(screenPos.xy, depth1));
			}
		#endif

		refractedDir *= min(distance(viewPos, viewPos1) * viewLengthInv, 4.0);
		refractedDir *= mix(0.125, 4.0, waterMask) * REFRACTION_STRENGTH;

		vec2 refractedCoord = ViewToScreenSpace(viewPos + refractedDir).xy;
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
	vec3 viewPos = ScreenToViewSpace(screenPos);
	#if defined LOD_MOD
		if (depth > 1.0 - EPS) {
			depth = screenPos.z = loadDepth0Lod(texelPos);
			viewPos = ScreenToViewSpaceLod(screenPos);
		}
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

    sceneOut = loadSceneMain(refractedTexel);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

	if (depth < 1.0) {
		vec4 translucent = ExtractSpecularTex(materialPack);

		// Particle translucent
		if (materialID == 500u) {
			vec3 diffuseLight = texelFetch(colortex3, texelPos, 0).rgb;
			vec3 albedo = sRGBtoLinear(translucent.rgb);
			sceneOut = mix(sceneOut, albedo * diffuseLight, translucent.a);
		}

		// Translucent
		if (glassMask || waterMask) {
			if (glassMask) {
				// Absorption
				vec3 absorption = log2(translucent.rgb);
				absorption *= 2.0 * sqrt2(translucent.a);
				sceneOut *= exp2(absorption);

				// Emissive
				sceneOut += (2.0 * EMISSIVE_BRIGHTNESS) * Unpack2x8UX(materialPack.x) * cube(translucent.rgb * translucent.a);
			}

			// Apply specular lighting
			vec4 specularLight = texelFetch(colortex3, texelPos, 0);
			sceneOut = sceneOut * specularLight.a + specularLight.rgb;
		}

		// Border fog
		#ifdef BORDER_FOG
			#if defined LOD_MOD
				#define far float(lodRenderDistance)
			#endif

			if (isEyeInWater == 0) {
				float density = saturate(1.0 - exp2(-pow8(sdot(worldPos.xz) * rcp(far * far)) * BORDER_FOG_FALLOFF));
				density *= exp2(-4.0 * curve(saturate(worldDir.y * 3.0)));

				vec3 skyRadiance = GetSkyRadiance(worldDir, worldSunVector);
				sceneOut = mix(sceneOut, skyRadiance, density);
			}
		#endif
	}

	// Initialize
	bloomyFogMask = 1.0;

	// Volumetric fog
	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			mat2x3 volFogData = VolumetricFogSpatialUpscale(texelPos >> 1, -viewPos.z);
			sceneOut = ApplyFog(sceneOut, volFogData);
			bloomyFogMask = mean(volFogData[1]);
		}
	#endif

	float viewDistance = length(viewPos);
	float LdotV = dot(worldLightVector, worldDir);

	// Underwater fog
	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 waterFog = VolumetricFogSpatialUpscale(texelPos >> 1, -viewPos.z);
		#else
			mat2x3 waterFog = AnalyticWaterFog(eyeSkylightSmooth, viewDistance, LdotV);
		#endif
		sceneOut = ApplyFog(sceneOut, waterFog);
		bloomyFogMask = mean(waterFog[1]);
	}

	// Vanilla fog
	RenderVanillaFog(sceneOut, bloomyFogMask, viewDistance);

	#if DEBUG_NORMALS == 1
		sceneOut = FetchSurfaceNormal(texelPos) * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneOut = FetchGeometryNormal(texelPos) * 0.5 + 0.5;
	#endif
}