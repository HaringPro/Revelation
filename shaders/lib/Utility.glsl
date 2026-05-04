/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/


#include "/settings.glsl"

#if defined VOXY || defined DISTANT_HORIZONS
	#define LOD_MOD
#endif

#if (SR_INSTALLED == 1) && (SR_ENABLE == 1)
    #undef TAA_ENABLED
#endif

#if defined(TAA_ENABLED) || (SR_ALGO_SUPPORTS_JITTER == 1 && SR_SHOULD_APPLY_JITTER == 1)
    #define SHOULD_APPLY_JITTER
#endif

#if SR_ENABLE == 1
    #define SUPER_RESOLUTION
    #undef MC_RENDER_SCALE_FACTOR
#endif

#define ApplyFog(scene, fog) ((scene) * fog[1] + fog[0])

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
