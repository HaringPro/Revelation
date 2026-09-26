#if !defined INCLUDE_LIB_LIGHTING_HANDHELD_ALBEDO
#define INCLUDE_LIB_LIGHTING_HANDHELD_ALBEDO

#ifndef HANDHELD_ALBEDO_ACCESS
	#define HANDHELD_ALBEDO_ACCESS readonly
#endif

#define HANDHELD_ALBEDO_BUCKET_COUNT 4096

const float handheldAlbedoQuantization = 4095.0;
const float handheldAlbedoHalflife = 0.25;
const uint handheldAlbedoStateMagic = 0x48414C42u;
const uint handheldAlbedoMaxMissingFrames = 8u;

layout(std430, binding = 3) HANDHELD_ALBEDO_ACCESS buffer HandheldAlbedoData {
	uvec4 buckets[HANDHELD_ALBEDO_BUCKET_COUNT];
	vec4 average;
	uvec4 state;
} handheldAlbedo;

#ifdef HANDHELD_ALBEDO_ACCUMULATE
	void AccumulateHandheldAlbedo(vec3 albedo, ivec2 texelPos) {
		uvec3 encodedAlbedo = uvec3(round(saturate(albedo) * handheldAlbedoQuantization));
		uvec4 encoded = uvec4(encodedAlbedo, 1u);

		#ifdef SUBGROUP_OPS
			encoded = subgroupAdd(encoded);
			if (!subgroupElect()) return;
		#endif

		uvec2 position = uvec2(texelPos);
		uint bucket = position.x * 0x1f123bb5u ^ position.y * 0x5f356495u;
		bucket ^= bucket >> 16u;
		bucket &= HANDHELD_ALBEDO_BUCKET_COUNT - 1u;

		atomicAdd(handheldAlbedo.buckets[bucket].r, encoded.r);
		atomicAdd(handheldAlbedo.buckets[bucket].g, encoded.g);
		atomicAdd(handheldAlbedo.buckets[bucket].b, encoded.b);
		atomicAdd(handheldAlbedo.buckets[bucket].a, encoded.a);
	}
#endif

#endif // INCLUDE_LIB_LIGHTING_HANDHELD_ALBEDO
