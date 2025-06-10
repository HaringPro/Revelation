/* Reflective Shadow Maps */
// Reference: https://users.soe.ucsc.edu/~pang/160/s13/proposal/mijallen/proposal/media/p203-dachsbacher.pdf

#define RSM_SAMPLES 16 // [4 8 12 16 20 24 32 48 64 96 128 256]
#define RSM_RADIUS 8.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 15.0 20.0 25.0 30.0 40.0 50.0 70.0 100.0]
#define RSM_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 40.0 50.0 70.0 100.0]

//================================================================================================//

uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

#include "ShadowDistortion.glsl"

//================================================================================================//

vec3 CalculateRSM(in vec3 viewPos, in vec3 worldNormal, in float dither, in float skyLightmap) {
	const float realShadowMapRes = float(shadowMapResolution) * MC_SHADOW_QUALITY;

	vec3 shadowNormal = mat3(shadowModelView) * worldNormal;
	vec3 projectionScale = diagonal3(shadowProjection);
	vec3 projectionInvScale = diagonal3(shadowProjectionInverse);

	vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
	vec3 shadowPos = transMAD(shadowModelView, worldPos);
	vec3 shadowClipPos = projectionScale * shadowPos + shadowProjection[3].xyz;

	const float sqRadius = RSM_RADIUS * RSM_RADIUS;
	const float rSteps = 1.0 / float(RSM_SAMPLES);

	const mat2 goldenRotate = mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle));

	vec2 offsetRadius = RSM_RADIUS * projectionScale.xy;
	vec2 dir = sincos(dither * 16.0 * PI) * offsetRadius;
	dither *= rSteps;

	vec3 sum = vec3(0.0);
	for (uint i = 0u; i < RSM_SAMPLES; ++i, dir *= goldenRotate) {
		float sampleRad 			= float(i) * rSteps + dither;

		vec2 sampleClipCoord 		= shadowClipPos.xy + dir * sampleRad;
		vec2 sampleScreenCoord		= sampleClipCoord * CalcDistortionFactor(sampleClipCoord) * 0.5 + 0.5;
		ivec2 sampleTexel 			= ivec2(sampleScreenCoord * realShadowMapRes);

		float sampleDepth 			= texelFetch(shadowtex1, sampleTexel, 0).x * 10.0 - 5.0;

		vec3 sampleDelta 			= vec3(sampleClipCoord, sampleDepth) - shadowClipPos;
		sampleDelta 				= projectionInvScale * sampleDelta;

		float sampleSqLen 	 		= sdot(sampleDelta);
		if (sampleSqLen > sqRadius) continue;

		vec3 sampleDir 				= sampleDelta * inversesqrt(sampleSqLen);

		float diffuse 				= dot(shadowNormal, sampleDir);
		if (diffuse < EPS) 		continue;

		vec3 sampleColor 			= texelFetch(shadowcolor1, sampleTexel, 0).rgb;

		vec3 sampleNormal 			= OctDecodeUnorm(sampleColor.xy);

		float bounce 				= dot(sampleNormal, -sampleDir);				
		if (bounce < EPS) 			continue;

		float falloff 	 			= sampleRad / (sampleSqLen + EPS);

		float skylightWeight 		= saturate(1.0 - sqr(sampleColor.z - skyLightmap) * 2.0);

		vec3 albedo 				= sRGBtoLinearApprox(texelFetch(shadowcolor0, sampleTexel, 0).rgb);

		sum += diffuse * bounce * falloff * skylightWeight * albedo;
	}

	sum *= sqRadius * rSteps * RSM_BRIGHTNESS * PI;

	return saturate(sum);
}