#if !defined INCLUDE_LIB_CLOUDS_PHASE_LUT
#define INCLUDE_LIB_CLOUDS_PHASE_LUT

#define CLOUD_PHASE_CU 0
#define CLOUD_PHASE_ST 1
#define CLOUD_PHASE_CI 2

const ivec2 cloudPhaseLutRes = ivec2(512, 3);

const float cloudPhaseEndpointDensity = 1.98;
const float cloudPhaseForwardBias = 0.84;

vec2 CloudPhaseLutUv(float cosTheta, int cloudType) {
	float angle = acos(satSnorm(cosTheta)) * rPI;
	float centered = fma(angle, 2.0, -1.0);
	float symmetric = fma(centered / mix(cloudPhaseEndpointDensity, 1.0, abs(centered)), 0.5, 0.5);
	float u = symmetric / mix(cloudPhaseForwardBias, 1.0, symmetric);
	vec2 uv = vec2(u, float(clamp(cloudType, CLOUD_PHASE_CU, CLOUD_PHASE_CI)));
	return UnitToSubUv(uv, vec2(cloudPhaseLutRes));
}

#if CLOUD_PHASE_LUT_COLORED

// The RGB LUT stores log2 of the normalized linear Rec.2020 phase function.
vec3 SampleCloudPhaseLut(float cosTheta, int cloudType) {
	vec2 uv = CloudPhaseLutUv(cosTheta, cloudType);
	return exp2(textureLod(cloudPhaseLut, uv, 0.0).rgb);
}

float SampleCloudPhaseLutScalar(float cosTheta, int cloudType) {
	return luminance(SampleCloudPhaseLut(cosTheta, cloudType));
}

#else

// The R LUT stores log2 of the normalized Rec.2020 luminance phase function.
float SampleCloudPhaseLutScalar(float cosTheta, int cloudType) {
	vec2 uv = CloudPhaseLutUv(cosTheta, cloudType);
	return exp2(textureLod(cloudPhaseLut, uv, 0.0).r);
}

#endif

#endif // INCLUDE_LIB_CLOUDS_PHASE_LUT
