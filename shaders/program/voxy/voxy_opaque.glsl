#include "/settings.glsl"

//======// Utility //=============================================================================//

#include "/lib/utility/Math.glsl"
#include "/lib/utility/Pack.glsl"

//======// Output //==============================================================================//

layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);
	vec3 color = parameters.sampledColour.rgb * parameters.tinting.rgb;

	albedoOut = vec4(color, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = PackupDithered2x8U(parameters.lightMap, bayer4(parameters.uv));
	materialOut.y = uint(parameters.customId - 10000);
	materialOut.zw = uvec2(0);

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}