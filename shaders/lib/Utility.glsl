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
#include "/lib/utility/Load.glsl"
#include "/lib/utility/Reshade.glsl"

//================================================================================================//

//================================================================================================//

struct FogData {
	vec3 scattering;
	vec3 transmittance;
};

#define ApplyFog(scene, fog) ((scene) * fog.transmittance + fog.scattering)