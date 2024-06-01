
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

const int shadowMapResolution = 2048;  // [1024 2048 4096 8192 16384 32768]

//----------------------------------------------------------------------------//

#include "ShadowDistortion.glsl"

vec3 WorldToShadowScreenPos(in vec3 worldPos) {
	vec3 shadowPos = transMAD(shadowModelView, worldPos);
	return projMAD(shadowProjection, shadowPos) * 0.5 + 0.5;
}

vec2 DistortShadowScreenPos(in vec2 shadowPos) {
	shadowPos = shadowPos * 2.0 - 1.0;
	shadowPos *= rcp(DistortionFactor(shadowPos));

	return shadowPos * 0.5 + 0.5;
}

//----------------------------------------------------------------------------//

vec3 CalculateRSM(in vec3 viewPos, in vec3 worldNormal, in float dither) {
	vec3 total = vec3(0.0);

	const float realShadowMapRes = shadowMapResolution * MC_SHADOW_QUALITY;
	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
	vec3 shadowScreenPos = WorldToShadowScreenPos(worldPos);

	vec3 shadowNormal = mat3(shadowModelView) * worldNormal;

	vec2 scale = GI_RADIUS * diagonal2(shadowProjection);
	const float sqRadius = GI_RADIUS * GI_RADIUS;
	const float rSteps = 1.0 / float(GI_SAMPLES);
	const float falloffScale = 12.0 / GI_RADIUS;

	float skyLightmap = texelFetch(colortex7, ivec2(gl_FragCoord.xy * 2.0), 0).g;

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 rot = sincos(dither * 64.0) * scale;
	dither *= rSteps;

	for (uint i = 0u; i < GI_SAMPLES; ++i, rot *= goldenRotate) {
		float sampleRad 			= float(i) * rSteps + dither;

		vec2 sampleCoord 			= shadowScreenPos.xy + rot * sampleRad;
		ivec2 sampleTexel 			= ivec2(DistortShadowScreenPos(sampleCoord) * realShadowMapRes);

		float sampleDepth 		= texelFetch(shadowtex1, sampleTexel, 0).x * 5.0 - 2.0;

		vec3 sampleVector 			= vec3(sampleCoord, sampleDepth) - shadowScreenPos;
		sampleVector 				= mat3(shadowProjectionInverse) * sampleVector;

		float sampleSqLen 	 		= dotSelf(sampleVector);
		if (sampleSqLen > sqRadius) continue;

		vec3 sampleDir 				= sampleVector * inversesqrt(sampleSqLen);

		float diffuse 				= saturate(dot(shadowNormal, sampleDir));
		if (diffuse < 1e-5) 		continue;

		vec3 sampleColor 			= texelFetch(shadowcolor1, sampleTexel, 0).rgb;

		vec3 sampleNormal 			= DecodeNormal(sampleColor.xy);

		float bounce 				= saturate(dot(sampleNormal, -sampleDir));				
		if (bounce < 1e-5) 			continue;

		float falloff 	 			= rcp((sampleSqLen + 0.5) * falloffScale + sampleRad);

		float skylightWeight 	= saturate(exp2(-sqr(sampleColor.z - skyLightmap)) * 2.5 - 1.5);

		// vec3 albedo 				= SRGBtoLinear(texelFetch(shadowcolor0, sampleTexel, 0).rgb);
		vec3 albedo 				= pow(texelFetch(shadowcolor0, sampleTexel, 0).rgb, vec3(2.2));

		total += albedo * falloff * diffuse * bounce * skylightWeight;
	}

	total *= sqRadius * rSteps;

	return total * inversesqrt(maxEps(total));
}
