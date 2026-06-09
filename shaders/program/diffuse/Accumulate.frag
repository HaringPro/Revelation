/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

	Pass: Accumulation and variance estimation
	Reference:  https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering://svgf_preprint.pdf
				https://cescg.org/wp-content/uploads/2018/04/Dundr-Progressive-Spatiotemporal-Variance-Guided-Filtering-2.pdf

--------------------------------------------------------------------------------
*/

const bool colortex3MipmapEnabled = true;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,14 */
layout(location = 0) out vec4 integratedDiffuse;
layout(location = 1) out vec3 encodedNormalDepth;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

void TemporalFilter(ivec2 texelPos, vec3 screenPos, vec3 worldNormal) {
	vec3 viewPos = ScreenToViewPos(screenPos);
	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

	vec3 prevWorldPos = worldPos + (cameraPosition - previousCameraPosition) * step(0.56, screenPos.z); // To previous frame's world space
	vec3 prevViewPos = transMAD(gbufferPreviousModelView, prevWorldPos); // To previous frame's view space
	vec3 prevNDCPos = projMAD(gbufferPreviousProjection, prevViewPos) * rcp(-prevViewPos.z); // To previous frame's NDC space

	#ifdef SHOULD_APPLY_JITTER
		prevNDCPos.xy += taaJitterPrev;
	#endif
	vec2 prevCoord = prevNDCPos.xy * 0.5 + 0.5;

	vec2 currCoord = texelToUvScaled(texelPos);
	encodedNormalDepth = vec3(OctEncodeSnorm(worldNormal), viewPos.z);

	if (saturate(prevCoord) == prevCoord && !historyReset) {
		vec4 prevDiffuse = vec4(0.0);
		float sumWeight = 0.0;

		// Custom bilinear filter
		vec2 prevTexel = (prevCoord * scaledViewSize
		- checkerboardOffset2x2[(frameCounter - 1) & 3u]
		- 0.5) * 0.5;

		ivec2 floorTexel = ivec2(floor(prevTexel));
		vec2 fractTexel = prevTexel - vec2(floorTexel);

		vec4 bilinearWeight = bilinear(fractTexel);

		float invThresholdZ = 8.0 / encodedNormalDepth.z;

		for (uint i = 0u; i < 4u; ++i) {
			ivec2 sampleTexel = floorTexel + offset2x2[i];
			if (clamp(sampleTexel, ivec2(0), ivec2(scaledHalfViewSize) - 1) == sampleTexel) {
				vec3 sampleAux = texelFetch(colortex14, sampleTexel, 0).xyz;
				vec4 sampleIrradiance = texelFetch(colortex2, sampleTexel, 0);

				float weight = saturate(fma(distance(encodedNormalDepth.z, sampleAux.z), invThresholdZ, 1.0));
				weight *= linearstep(0.5, 0.8, saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal)));
				weight *= bilinearWeight[i];

				prevDiffuse += sampleIrradiance * weight;
				sumWeight += weight;
			}
		}

		if (sumWeight > EPS) {
			sumWeight = 1.0 / sumWeight;
			prevDiffuse *= sumWeight;

			integratedDiffuse.a = min(prevDiffuse.a + 1.0, SSILVB_MAX_ACCUM_FRAMES);

			if (integratedDiffuse.a < 8.0) {
				float mipLevel = 3.0 * saturate(1.0 - integratedDiffuse.a * rcp(8.0));
				integratedDiffuse.rgb = textureLod(colortex3, currCoord, mipLevel).rgb;
			} else {
				integratedDiffuse.rgb = texelFetch(colortex3, texelPos, 0).rgb;
			}

			float alpha = rcp(integratedDiffuse.a);
			integratedDiffuse.rgb = mix(min(prevDiffuse.rgb, FP16_MAX), integratedDiffuse.rgb, alpha);
			return;
		}
	}

	integratedDiffuse.rgb = textureLod(colortex3, currCoord, 3.0).rgb;
}

float GetClosestDepthN(ivec2 texel) {
	float depth = 1.0;

	for (uint i = 0u; i < 8u; ++i) {
		ivec2 sampleTexel = offset3x3N[i] + texel;
		float sampleDepth = loadDepth0(sampleTexel);
		depth = min(depth, sampleDepth);
	}

	return depth;
}

//======// Main //================================================================================//
void main() {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);

	ivec2 renderTexel = texelPos * 2 + checkerboardOffset2x2[frameCounter & 3u];
	vec2 renderCoord = texelToUvScaled(renderTexel);

	float depth = loadDepth0(renderTexel);
	bool terrainCheck = lessThanFLT1(min(GetClosestDepthN(renderTexel), depth));
	#if defined LOD_MOD
		bool lodMask = !terrainCheck;
		if (lodMask) {
			depth = loadDepth0Lod(renderTexel);
			terrainCheck = lessThanFLT1(depth);
		}
	#endif

	integratedDiffuse = vec4(0.0);
	encodedNormalDepth = vec3(0.0);

	if (terrainCheck) {
		#if defined LOD_MOD
			if (lodMask) depth = ViewToScreenDepth(ScreenToViewDepthLod(depth));
		#endif

		vec3 screenPos = vec3(renderCoord, depth);
		vec3 worldNormal = FetchSurfaceNormal(renderTexel);

		TemporalFilter(texelPos, screenPos, worldNormal);
	}
}
