#if !defined INCLUDE_LIB_SHADOW_CAUSTIC
#define INCLUDE_LIB_SHADOW_CAUSTIC

vec2 WaterRefractionSlope(vec3 encodedNormal) {
	vec3 waveNormal = normalize(encodedNormal * 2.0 - 1.0);
	vec3 refractDir = refract(-shadowDirWorld, waveNormal, 1.0 / WATER_IOR);

	return refractDir.xz * rcp(abs(refractDir.y));
}

vec2 WaterRefractionOffset(vec3 encodedNormal, float waterDepth, vec2 flatSlope) {
	return (WaterRefractionSlope(encodedNormal) - flatSlope) * waterDepth;
}

float EvaluateWaterMapping(
	vec3 sourceWorldPos, float projectionDepth, float footprint, vec2 flatSlope,
	out vec2 offsetCenter, out vec2 jacobianX, out vec2 jacobianZ
) {
	vec3 shadowClipPos = projMAD(shadowProjection, transMAD(shadowModelView, sourceWorldPos));
	vec3 shadowClipStepX = diagonal3(shadowProjection) * (mat3(shadowModelView)[0] * footprint);
	vec3 shadowClipStepZ = diagonal3(shadowProjection) * (mat3(shadowModelView)[2] * footprint);
	vec2 shadowCoord = (DistortShadowSpace(shadowClipPos) * 0.5 + 0.5).xy;
	vec2 shadowTexel = clamp(
		shadowCoord * realShadowMapRes - 0.5,
		vec2(0.0), vec2(realShadowMapRes - 1.001)
	);
	ivec2 texel00 = ivec2(floor(shadowTexel));
	vec2 texelFract = shadowTexel - vec2(texel00);

	// Reconstruct a continuous refraction field from one shadow texel quad.
	vec4 sample00 = texelFetch(shadowcolor1, texel00, 0);
	vec4 sample10 = texelFetch(shadowcolor1, texel00 + ivec2(1, 0), 0);
	vec4 sample01 = texelFetch(shadowcolor1, texel00 + ivec2(0, 1), 0);
	vec4 sample11 = texelFetch(shadowcolor1, texel00 + ivec2(1, 1), 0);
	vec2 offset00 = WaterRefractionOffset(sample00.xyz, projectionDepth, flatSlope);
	vec2 offset10 = WaterRefractionOffset(sample10.xyz, projectionDepth, flatSlope);
	vec2 offset01 = WaterRefractionOffset(sample01.xyz, projectionDepth, flatSlope);
	vec2 offset11 = WaterRefractionOffset(sample11.xyz, projectionDepth, flatSlope);

	vec2 offset0 = mix(offset00, offset10, texelFract.x);
	vec2 offset1 = mix(offset01, offset11, texelFract.x);
	offsetCenter = mix(offset0, offset1, texelFract.y);
	vec2 offsetTexelX = mix(offset10 - offset00, offset11 - offset01, texelFract.y);
	vec2 offsetTexelY = mix(offset01 - offset00, offset11 - offset10, texelFract.x);

	float texelScale = realShadowMapRes / footprint;
	vec2 shadowGradX = (
		(DistortShadowSpace(shadowClipPos + shadowClipStepX) * 0.5 + 0.5).xy - shadowCoord
	) * texelScale;
	vec2 shadowGradZ = (
		(DistortShadowSpace(shadowClipPos + shadowClipStepZ) * 0.5 + 0.5).xy - shadowCoord
	) * texelScale;
	jacobianX = vec2(1.0, 0.0)
		+ offsetTexelX * shadowGradX.x + offsetTexelY * shadowGradX.y;
	jacobianZ = vec2(0.0, 1.0)
		+ offsetTexelX * shadowGradZ.x + offsetTexelY * shadowGradZ.y;

	return min(min(sample00.w, sample10.w), min(sample01.w, sample11.w));
}

vec3 CalculateWaterCaustics(vec3 worldPos, float waterDepth, vec3 encodedNormal) {
	float projectionDepth = clamp(approxSqrt(waterDepth), 2.0, 16.0);
	float shadowFootprint = 2.0 / realShadowMapRes * abs(shadowProjectionInverse[0].x);
	float footprint = max(shadowFootprint, 0.05 * projectionDepth);

	vec3 flatRefractDir = refract(-shadowDirWorld, vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
	vec2 flatSlope = flatRefractDir.xz * rcp(abs(flatRefractDir.y));
	vec2 targetSlope = WaterRefractionSlope(encodedNormal);
	vec2 targetPos = worldPos.xz;
	vec2 targetOffset = (targetSlope - flatSlope) * projectionDepth;
	vec2 sourcePos = targetPos - targetOffset;
	vec3 sourceWorldPos = worldPos;
	sourceWorldPos.xz = sourcePos;

	vec2 offsetCenter, jacobianX, jacobianZ;
	float validMask = EvaluateWaterMapping(
		sourceWorldPos, projectionDepth, footprint, flatSlope,
		offsetCenter, jacobianX, jacobianZ
	);

	float opticalDepth = waterDepth * approxSqrt(1.0 + sdot(targetSlope));
	vec3 transmittance = saturate(exp2(-rLOG2 * waterExtinction * opticalDepth));
	if (validMask < EPS) return transmittance;

	float jacobianDet = jacobianX.x * jacobianZ.y - jacobianZ.x * jacobianX.y;
	vec2 mappingError = sourcePos + offsetCenter - targetPos;
	vec2 correction = vec2(
		jacobianZ.y * mappingError.x - jacobianZ.x * mappingError.y,
		jacobianX.x * mappingError.y - jacobianX.y * mappingError.x
	) * (signI(jacobianDet) / maxEps(abs(jacobianDet)));
	correction *= saturate(4.0 * footprint * inversesqrt(maxEps(sdot(correction))));

	sourcePos -= correction;
	sourceWorldPos.xz = sourcePos;
	validMask *= EvaluateWaterMapping(
		sourceWorldPos, projectionDepth, footprint, flatSlope,
		offsetCenter, jacobianX, jacobianZ
	);

	jacobianDet = jacobianX.x * jacobianZ.y - jacobianZ.x * jacobianX.y;
	mappingError = sourcePos + offsetCenter - targetPos;

	float mappingValidity = exp2(-sdot(mappingError) / (32.0 * footprint * footprint));
	float compression = rcp(max(abs(jacobianDet), 0.1));
	float focus = mix(1.0, compression, validMask * mappingValidity);

	return focus * transmittance;
}

#endif // INCLUDE_LIB_SHADOW_CAUSTIC
