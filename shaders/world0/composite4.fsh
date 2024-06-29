#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,6 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogTrans;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Uniform //=============================================================================//

uniform sampler2D colortex11;
uniform sampler2D colortex12;

#include "/lib/utility/Uniform.glsl"

//======// Struct //==============================================================================//

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"

#include "/lib/atmospherics/Global.inc"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

#include "/lib/surface/Refraction.glsl"
#include "/lib/water/WaterFog.glsl"

#include "/lib/surface/BRDF.glsl"

vec4 CalculateSpecularReflections(in vec3 viewNormal, in float skylight, in vec3 screenPos, in vec3 viewPos) {
	skylight = smoothstep(0.3, 0.8, cube(skylight));
	vec3 viewDir = normalize(viewPos);

	float LdotH = dot(viewNormal, -viewDir);
	vec3 rayDir = viewDir + viewNormal * LdotH * 2.0;

	float NdotL = dot(viewNormal, rayDir);
	if (NdotL < 1e-6) return vec4(0.0);

	vec3 reflection;
	if (skylight > 1e-3) {
		if (isEyeInWater == 0) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld) + vec2(0.0, 0.5)).rgb;

			reflection = skyRadiance * skylight;
		}
	}

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
		reflection += (texelFetch(colortex4, rawCoord(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade * 8e2);
	}

	float NdotV = max(1e-6, dot(viewNormal, -viewDir));
	float brdf = FresnelDielectricN(NdotV, GLASS_REFRACT_IOR);

	return vec4(reflection, brdf);
}

mat2x3 VolumetricFogSpatialUpscale(in vec2 coord, in float linearDepth) {
	ivec2 bias = ivec2(coord + frameCounter) % 2;
	ivec2 texel = ivec2(coord * 0.5) + bias * 2;

	const ivec2 offset[4] = ivec2[4](
		ivec2(-2,-2), ivec2(-2, 0),
		ivec2( 0, 0), ivec2( 0,-2)
	);

	float sigmaZ = 64.0 / linearDepth;
	mat2x3 total = mat2x3(0.0);
	float sumWeight = 0.0;

	for (uint i = 0u; i < 4u; ++i) {
		ivec2 sampleTexel = texel + offset[i];
		float sampleDepth = ScreenToLinearDepth(sampleDepth(sampleTexel * 2));
		float weight = maxEps(exp2(-abs(sampleDepth - linearDepth) * sigmaZ));
		total += mat2x3(texelFetch(colortex11, sampleTexel, 0).rgb, texelFetch(colortex12, sampleTexel, 0).rgb) * weight;
		sumWeight += weight;
	}

	return total / sumWeight;
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
	vec4 gbufferData0 = sampleGbufferData0(screenTexel);
	vec2 lightmap = unpackUnorm2x8(gbufferData0.x);

	uint materialID = uint(gbufferData0.y * 255.0);

	float depth = GetDepthFix(screenTexel);
	float sDepth = GetDepthSoildFix(screenTexel);

	#ifdef BORDER_FOG
		bool doBorderFog = depth < 1.0 && isEyeInWater == 0;
	#endif

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);
	vec3 sViewPos = ScreenToViewSpace(vec3(screenCoord, sDepth));

	float viewDistance = length(viewPos);
	float transparentDepth = distance(viewPos, sViewPos);

	vec4 gbufferData1 = texelFetch(colortex8, screenTexel, 0);
	vec3 worldNormal = GetWorldNormal(gbufferData0);
	vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

	vec2 refractCoord;
	ivec2 refractTexel;
	bool waterMask = false;
	if (materialID == 2u || materialID == 3u) {
		#ifdef RAYTRACED_REFRACTION
			refractCoord = CalculateRefractCoord(viewPos, viewNormal, screenPos);
		#else	
			refractCoord = CalculateRefractCoord(materialID, viewPos, viewNormal, gbufferData1, transparentDepth);
		#endif
		refractTexel = rawCoord(refractCoord);
		if (sampleDepthSoild(refractTexel) < depth) {
			refractCoord = screenCoord;
			refractTexel = screenTexel;
		}

		depth = sampleDepth(refractTexel);
		sDepth = sampleDepthSoild(refractTexel);

		gbufferData0 = texelFetch(colortex7, refractTexel, 0);
		waterMask = uint(gbufferData0.y * 255.0) == 3u || materialID == 3u;
	} else {
		refractCoord = screenCoord;
		refractTexel = screenTexel;
	}

    sceneOut = sampleSceneColor(refractTexel);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	worldPos += gbufferModelViewInverse[3].xyz;


	float LdotV = dot(worldLightVector, worldDir);

	if (waterMask && isEyeInWater == 0) {
		float waterDepth = distance(ScreenToViewSpace(vec3(refractCoord, depth)), ScreenToViewSpace(vec3(refractCoord, sDepth)));
		mat2x3 waterFog = CalculateWaterFog(lightmap.y, max(transparentDepth, waterDepth), LdotV);
		sceneOut = sceneOut * waterFog[1] + waterFog[0];
	}

	if (waterMask || materialID == 2u) {
		// Specular reflections of water and lighting of glass
		vec4 blendedData = texelFetch(colortex2, screenTexel, 0);
		sceneOut += (blendedData.rgb - sceneOut) * blendedData.a;
		if (materialID == 2u) {
			// Glass tint
			vec4 translucents = vec4(unpackUnorm2x8(gbufferData1.x), unpackUnorm2x8(gbufferData1.y));
			translucents.a = fastSqrt(fastSqrt(translucents.a));
			sceneOut *= cube((1.0 - translucents.a + saturate(translucents.rgb)) * translucents.a);

			// Specular reflections of glass
			vec4 reflections = CalculateSpecularReflections(viewNormal, lightmap.y, screenPos, viewPos);
			sceneOut += (reflections.rgb - sceneOut) * reflections.a;
		}
	} else if (materialID == 51u) {
		// Specular reflections of slime
		vec4 reflections = CalculateSpecularReflections(viewNormal, lightmap.y, screenPos, viewPos);
		sceneOut += (reflections.rgb - sceneOut) * reflections.a;
	}

	#ifdef BORDER_FOG
		if (doBorderFog) {
			float density = saturate(1.0 - exp2(-sqr(pow4(dotSelf(worldPos.xz) * rcp(far * far))) * BORDER_FOG_FALLOFF));
			density *= exp2(-5.0 * curve(saturate(worldDir.y * 3.0)));

			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(worldDir)).rgb;
			sceneOut = mix(sceneOut, skyRadiance, density);
		}
	#endif

	bloomyFogTrans = 1.0;
	#ifdef VOLUMETRIC_FOG
		if (isEyeInWater == 0) {
			mat2x3 volFogData = VolumetricFogSpatialUpscale(gl_FragCoord.xy, ScreenToLinearDepth(depth));
			sceneOut = sceneOut * volFogData[1] + volFogData[0];
			bloomyFogTrans = min(bloomyFogTrans, dot(volFogData[1], vec3(0.333333)));
		}
	#endif

	if (isEyeInWater == 1) {
		#ifdef UW_VOLUMETRIC_FOG
			mat2x3 volFogData = VolumetricFogSpatialUpscale(gl_FragCoord.xy, ScreenToLinearDepth(depth));
			sceneOut = sceneOut * volFogData[1] + volFogData[0];
			bloomyFogTrans = min(bloomyFogTrans, dot(volFogData[1], vec3(0.333333)));
		#else
			mat2x3 waterFog = CalculateWaterFog(saturate(eyeSkylightFix + 0.2), viewDistance, LdotV);
			sceneOut = sceneOut * waterFog[1] + waterFog[0];
			bloomyFogTrans = dot(waterFog[1], vec3(0.333333));
		#endif
	}

	#if DEBUG_NORMALS == 1
		sceneOut = worldNormal * 0.5 + 0.5;
	#elif DEBUG_NORMALS == 2
		sceneOut = GetFlatNormal(gbufferData0) * 0.5 + 0.5;
	// #elif DEBUG_DEPTH == 1
	// 	sceneOut = vec3(depth);
	// #elif DEBUG_DEPTH == 2
	// 	sceneOut = vec3(sDepth);
	#endif
}