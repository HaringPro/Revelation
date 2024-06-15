#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,6 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogTrans;

//======// Input //===============================================================================//

in vec2 screenCoord;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Attribute //===========================================================================//

//======// Uniform //=============================================================================//

#include "/lib/utility/Uniform.inc"

//======// Struct //==============================================================================//

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Noise.inc"

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

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);

	vec3 reflection;
	if (skylight > 1e-3) {
		if (isEyeInWater == 0) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld)).rgb;

			reflection = skyRadiance * skylight;
		}
	}

	float NdotV = max(1e-6, dot(viewNormal, -viewDir));
	bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		vec2 previousCoord = Reproject(screenPos).xy;
		if (saturate(previousCoord) == previousCoord) {
			float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
			reflection += (texelFetch(colortex7, rawCoord(previousCoord), 0).rgb - reflection) * saturate(edgeFade * 7e2);
		}
	}

	float brdf = FresnelDielectricN(NdotV, GLASS_REFRACT_IOR);

	return vec4(reflection, brdf);
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
	vec4 gbufferData0 = texelFetch(colortex3, screenTexel, 0);
	vec2 lightmap = unpackUnorm2x8(gbufferData0.x);

	uint materialID = uint(gbufferData0.y * 255.0);

	float depth = GetDepthFix(screenTexel);
	float sDepth = GetDepthSoildFix(screenTexel);

	vec3 screenPos = vec3(screenCoord, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);
	vec3 sViewPos = ScreenToViewSpace(vec3(screenCoord, sDepth));

	float viewDistance = length(viewPos);
	float transparentDepth = distance(viewPos, sViewPos);

	vec4 gbufferData1 = texelFetch(colortex4, screenTexel, 0);
	vec3 viewNormal = mat3(gbufferModelView) * GetWorldNormal(gbufferData0);

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

		gbufferData0 = texelFetch(colortex3, refractTexel, 0);
		waterMask = uint(gbufferData0.y * 255.0) == 3u;
	} else {
		refractCoord = screenCoord;
		refractTexel = screenTexel;
	}

    sceneOut = sampleSceneColor(refractTexel);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	worldPos += gbufferModelViewInverse[3].xyz;


	float LdotV = dot(worldLightVector, worldDir);

	bloomyFogTrans = 1.0;
	if (isEyeInWater == 1) {
		mat2x3 waterFog = CalculateWaterFog(saturate(eyeSkylightFix + 0.2), viewDistance, LdotV);
		sceneOut = sceneOut * waterFog[1] + waterFog[0];
		bloomyFogTrans = dot(waterFog[1], vec3(0.333333));
	} else if (waterMask) {
		float waterDepth = distance(ScreenToViewSpace(vec3(refractCoord, depth)), ScreenToViewSpace(vec3(refractCoord, sDepth)));
		mat2x3 waterFog = CalculateWaterFog(lightmap.y, waterDepth, LdotV);
		sceneOut = sceneOut * waterFog[1] + waterFog[0];
	}

	if (waterMask || materialID == 2u) {
		// Specular reflections of Water and lighting of glass
		vec4 blendedData = texelFetch(colortex2, screenTexel, 0);
		sceneOut += (blendedData.rgb - sceneOut) * blendedData.a;
		if (materialID == 2u) {
			// Glass tint
			vec4 translucents = vec4(unpackUnorm2x8(gbufferData1.x), unpackUnorm2x8(gbufferData1.y));
			translucents.a = sqrt2(translucents.a);
			sceneOut *= cube(1.0 - translucents.a + saturate(translucents.rgb * translucents.a) * translucents.a);

			// Specular reflections of glass
			vec4 reflections = CalculateSpecularReflections(viewNormal, lightmap.y, screenPos, viewPos);
			sceneOut += (reflections.rgb - sceneOut) * reflections.a;
		}
	} else if (materialID == 51u) {
		vec4 reflections = CalculateSpecularReflections(viewNormal, lightmap.y, screenPos, viewPos);
		sceneOut += (reflections.rgb - sceneOut) * reflections.a;
	}

	#ifdef BORDER_FOG
		if (depth + isEyeInWater < 1.0) {
			float density = saturate(1.0 - exp2(-sqr(pow4(dotSelf(worldPos.xz) * rcp(far * far))) * BORDER_FOG_FALLOFF));
			density *= oneMinus(saturate(worldDir.y * 3.0));

			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(worldDir)).rgb;
			sceneOut = mix(sceneOut, skyRadiance, density);
		}
	#endif
}