#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Combine indirect lighting

--------------------------------------------------------------------------------
*/

layout (local_size_x = 16, local_size_y = 16) in;
const vec2 workGroupsRender = vec2(1.0f, 1.0f);

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

layout (r11f_g11f_b10f) restrict uniform image2D colorimg0; // Scene color

//======// Uniform //=============================================================================//

layout (rgba16f) restrict readonly uniform image2D colorimg3; // Current indirect light

uniform sampler2D colortex6; // Albedo
uniform sampler2D colortex7; // Gbuffer data 0

uniform sampler2D colortex13; // Previous indirect light

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform float near;
uniform float far;
uniform float viewWidth;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 taaOffset;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Offset.glsl"

#ifdef SVGF_ENABLED
	vec3 SpatialUpscale3x3(in vec3 worldNormal, in float viewDistance, in float NdotV) {
		ivec2 texel = ivec2(gl_GlobalInvocationID.xy / 2);

		float sumWeight = 0.1;

		vec3 total = imageLoad(colorimg3, texel).rgb;
		float centerLuma = GetLuminance(total);
		total *= sumWeight;

		ivec2 shift = ivec2(viewWidth * 0.5, 0);
        ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = texel + offset3x3N[i];
			if (clamp(sampleTexel, ivec2(0), maxLimit) == sampleTexel) {
				vec3 sampleLight = imageLoad(colorimg3, sampleTexel).rgb;

				vec4 prevData = texelFetch(colortex13, sampleTexel + shift, 0);

				float weight = pow16(max0(dot(prevData.rgb, worldNormal)));
				weight *= exp2(-distance(prevData.a, viewDistance) * NdotV);
				weight *= exp2(-abs(centerLuma - GetLuminance(sampleLight.rgb)) * 0.4);

				total += sampleLight * weight;
				sumWeight += weight;
			}
		}

		return total / sumWeight;
	}

	vec3 SpatialUpscale5x5(in vec3 worldNormal, in float viewDistance, in float NdotV) {
		ivec2 texel = ivec2(gl_GlobalInvocationID.xy / 2);

		float sumWeight = 0.1;

		vec3 total = imageLoad(colorimg3, texel).rgb;
		float centerLuma = GetLuminance(total);
		total *= sumWeight;

		ivec2 shift = ivec2(viewWidth * 0.5, 0);
        ivec2 maxLimit = ivec2(viewSize * 0.5) - 1;

		for (uint i = 0u; i < 24u; ++i) {
			ivec2 sampleTexel = texel + offset5x5N[i];
			if (clamp(sampleTexel, ivec2(0), maxLimit) == sampleTexel) {
				vec3 sampleLight = imageLoad(colorimg3, sampleTexel).rgb;

				vec4 prevData = texelFetch(colortex13, sampleTexel + shift, 0);

				float weight = pow16(max0(dot(prevData.rgb, worldNormal)));
				weight *= exp2(-distance(prevData.a, viewDistance) * NdotV);
				weight *= exp2(-abs(centerLuma - GetLuminance(sampleLight.rgb)) * 0.4);

				if (weight < 1e-5) continue;

				total += sampleLight * weight;
				sumWeight += weight;
			}
		}

		return total / sumWeight;
	}
#endif

//======// Main //================================================================================//
void main() {
	ivec2 screenTexel = ivec2(gl_GlobalInvocationID.xy);

	float depth = sampleDepth(screenTexel);

	if (depth < 1.0) {
		#ifdef DEBUG_GI
			vec3 albedo = vec3(1.0);
			vec3 sceneOut = vec3(0.0);
		#else
			vec3 albedo = sRGBtoLinear(sampleAlbedo(screenTexel));
			vec3 sceneOut = imageLoad(colorimg0, screenTexel).rgb;
		#endif

		// Global illumination
		#ifdef SVGF_ENABLED
			vec2 screenCoord = vec2(gl_GlobalInvocationID.xy) * viewPixelSize;
			vec3 screenPos = vec3(screenCoord, depth);
			vec3 viewPos = ScreenToViewSpace(screenPos);

			vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewPos);

			vec4 gbufferData0 = sampleGbufferData0(screenTexel);

			vec3 worldNormal = FetchWorldNormal(gbufferData0);
			float NdotV = saturate(dot(worldNormal, -worldDir));

			sceneOut += SpatialUpscale5x5(worldNormal, length(viewPos), NdotV) * albedo;
		#else
			sceneOut += imageLoad(colorimg3, screenTexel / 2).rgb * albedo;
		#endif

		// Minimal ambient light
		// sceneOut = max(sceneOut, albedo * MINIMUM_AMBIENT_BRIGHTNESS);

		imageStore(colorimg0, screenTexel, vec4(sceneOut, 1.0));
	}
}