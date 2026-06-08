#if !defined INCLUDE_UTILITY_COMPAT
#define INCLUDE_UTILITY_COMPAT

#if defined MC_GL_NV_gpu_shader5
	#extension GL_NV_gpu_shader5 : enable
#elif defined MC_GL_AMD_gpu_shader_half_float
	#extension GL_AMD_gpu_shader_half_float : enable
#else
	#define float16_t float
	#define f16vec2 vec2
	#define f16vec3 vec3
	#define f16vec4 vec4

	#define f16mat2 mat2
	#define f16mat2x2 mat2x2
	#define f16mat2x3 mat2x3
	#define f16mat2x4 mat2x4

	#define f16mat3 mat3
	#define f16mat3x2 mat3x2
	#define f16mat3x3 mat3x3
	#define f16mat3x4 mat3x4

	#define f16mat4 mat4
	#define f16mat4x2 mat4x2
	#define f16mat4x3 mat4x3
	#define f16mat4x4 mat4x4
#endif

#ifndef FORCE_DISABLE_SUBGROUP_OPS
	#if defined GL_KHR_shader_subgroup || defined MC_GL_KHR_shader_subgroup
		#define SUBGROUP_OPS
	#endif
#endif

#ifdef SUBGROUP_OPS
	#ifdef MC_GL_VENDOR_AMD
		#define SCALARIZED_LOAD(a, b) (a) = subgroupBroadcastFirst(b)
	#else
		#define SCALARIZED_LOAD(a, b) if (subgroupElect()) { (a) = (b); }
	#endif
#endif

#endif // INCLUDE_UTILITY_COMPAT
