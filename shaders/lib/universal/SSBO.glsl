#ifndef SSBO_DECLARED_TPYE
#define SSBO_DECLARED_TPYE readonly
#endif

layout (std430, binding = 0) SSBO_DECLARED_TPYE buffer GlobalData {
	int prevWorldTime;
	bool historyReset;
	vec3 directIlluminance;
	vec3 skyUpIlluminance;
	vec3[9] skySH;
} global;

layout (std430, binding = 1) SSBO_DECLARED_TPYE buffer ExposureData {
	uint histogram[HISTOGRAM_BIN_COUNT];
	float value;
} exposure;

layout (std430, binding = 2) SSBO_DECLARED_TPYE buffer CloudData {
	mat4 shadowViewProj;
	mat4 shadowViewProjInv;
} cloud;
