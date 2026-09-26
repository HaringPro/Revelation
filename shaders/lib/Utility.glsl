#if !defined INCLUDE_LIB_UTILITY
#define INCLUDE_LIB_UTILITY

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/


#include "/lib/Setting.glsl"

#if defined VOXY || defined DISTANT_HORIZONS
	#define LOD_MOD
#endif

#define lessThanFLT1(x) (floatBitsToUint(x) < 0x3F800000u)

#if SR_INSTALLED && SR_ENABLE
    #undef TAA_ENABLED
    #undef CLOUD_TAAU_ENABLED
    #undef CAS_ENABLED
#endif

#if defined(TAA_ENABLED) || (SR_ALGO_SUPPORTS_JITTER && SR_SHOULD_APPLY_JITTER)
    #define SHOULD_APPLY_JITTER
#endif

#if SR_ENABLE
    #undef RENDER_SCALE
    #define RENDER_SCALE SR_RENDER_SCALE_FACTOR
    #undef RENDER_SCALE_HALF
    #define RENDER_SCALE_HALF SR_RENDER_SCALE_FACTOR_HALF
#endif

#include "/lib/utility/Compat.glsl"
#include "/lib/utility/Math.glsl"
#include "/lib/utility/Matrix.glsl"
#include "/lib/utility/Pack.glsl"
#include "/lib/utility/Color.glsl"
#include "/lib/utility/Interpolate.glsl"
#include "/lib/utility/Phase.glsl"
#include "/lib/utility/SH.glsl"
#include "/lib/utility/Offset.glsl"
#include "/lib/utility/Load.glsl"
#include "/lib/utility/Compute.glsl"
#include "/lib/utility/RenderScale.glsl"

#endif // INCLUDE_LIB_UTILITY
