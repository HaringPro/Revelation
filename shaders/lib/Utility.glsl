/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/


#include "/settings.glsl"

#include "/lib/utility/Math.glsl"
#include "/lib/utility/Pack.glsl"
#include "/lib/utility/Color.glsl"
#include "/lib/utility/Texture.glsl"
#include "/lib/utility/Phase.glsl"
#include "/lib/utility/Load.glsl"

//================================================================================================//

#if defined MC_GL_VENDOR_AMD
	#define SCALARIZED_LOAD(a, b) a = subgroupBroadcastFirst(b)
#else
	#define SCALARIZED_LOAD(a, b) if (subgroupElect()) { a = b; }
#endif

#define ApplyFog(scene, fog) ((scene) * fog[1] + fog[0])
