#if !defined INCLUDE_LIB_POST_DOF
#define INCLUDE_LIB_POST_DOF

const float DOF_SENSOR_WIDTH = 0.036;
const float dofFocalLength = DOF_FOCAL_LENGTH * 0.001;
const float dofApertureRadius = 0.5 * dofFocalLength / DOF_F_STOP;
const vec2 dofPairRotation = vec2(-0.3623748901, 0.9320324238);
const float dofPairPhase = 0.3090169944;

const float dofHexCircumradius = 1.099636111;
const vec2 dofHexVertices[7] = vec2[7](
    vec2(1.0, 0.0),
    vec2(0.5, 0.8660254),
    vec2(-0.5, 0.8660254),
    vec2(-1.0, 0.0),
    vec2(-0.5, -0.8660254),
    vec2(0.5, -0.8660254),
    vec2(1.0, 0.0)
);

float DofCoCScale(float focusDepth) {
	float focusRange = maxEps(focusDepth - dofFocalLength);
	return dofApertureRadius * dofFocalLength * scaledViewSize.x * rcp(DOF_SENSOR_WIDTH * focusRange);
}

float DofCoCRadius(float viewDepth, float focusDepth, float cocScale, float maxBlurRadius) {
	float texelRadius = cocScale * (viewDepth - focusDepth) / maxEps(viewDepth);
	return clamp(texelRadius, -maxBlurRadius, maxBlurRadius);
}

vec2 DofRotatePair(vec2 direction) {
	return vec2(
		direction.x * dofPairRotation.x - direction.y * dofPairRotation.y,
		direction.x * dofPairRotation.y + direction.y * dofPairRotation.x
	);
}

vec2 DofApertureOffset(vec2 direction, float aperturePhase, float radius) {
	#if DOF_APERTURE_SHAPE == 1
		float edgePos = fract(aperturePhase) * 6.0;
		int edgeIndex = min(int(edgePos), 5);
		vec2 boundary = mix(dofHexVertices[edgeIndex], dofHexVertices[edgeIndex + 1], fract(edgePos));
		return boundary * (radius * dofHexCircumradius);
	#else
		return direction * radius;
	#endif
}

#ifdef DOF_APERTURE_VIGNETTING
	vec3 DofApertureVignettingPrepare(vec2 centerUv) {
		vec2 centerPos = centerUv - 0.5;
		float centerRadiusSq = sdot(centerPos);
		float centerRadiusInv = inversesqrt(maxEps(centerRadiusSq));
		float compression = centerRadiusSq * centerRadiusInv;
        compression *= 4.0 * gbufferProjectionInverse[1].y;
		return vec3(centerPos * centerRadiusInv, compression);
	}

	void DofApertureVignettingApply(inout vec2 sampleOffset, float kernelRadius, vec3 vignettingData) {
		float radialOffset = dot(sampleOffset, vignettingData.xy);
		float radialWarp = (radialOffset + kernelRadius) * vignettingData.z;
		sampleOffset -= vignettingData.xy * radialWarp;
	}
#endif

float DofApertureCoverage(float cocRadius, float sampleDistance, float maxBlurRadius) {
	return saturate((cocRadius - sampleDistance) * maxBlurRadius + 0.5);
}

vec2 DofMirrorUv(vec2 uv) {
	uv = max(uv, -uv);
	uv = min(uv, 2.0 - uv);
	return saturate(uv);
}

float DofVogelRadius(uint sampleIndex, float radialPhase, float inverseSampleCount) {
	float radiusSq = float(sampleIndex) * inverseSampleCount + radialPhase;
	return radiusSq * inversesqrt(maxEps(radiusSq));
}

#endif // INCLUDE_LIB_POST_DOF
