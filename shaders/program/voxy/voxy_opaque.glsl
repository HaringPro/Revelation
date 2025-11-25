#include "/settings.glsl"

//======// Utility //=============================================================================//

// #include "/lib/utility/Load.glsl"
// #define loadDepthOpaqueLod(texel) 			texelFetch(vxDepthTexOpaque, texel, 0).x
#include "/lib/utility/Math.glsl"
#include "/lib/utility/Pack.glsl"

//======// Output //==============================================================================//

layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

// #include "/lib/universal/Transform.glsl"
// vec3 ProjectDivide(in vec3 v, in mat4 m) {
// 	return projMAD(m, v) * rcp(m[2].w * v.z + m[3].w);
// }
// vec3 ScreenToViewSpaceRawVoxy(in vec3 screenPos) {
// 	vec3 NDCPos = screenPos * 2.0 - 1.0;
// 	return ProjectDivide(NDCPos, vxProjInv);
// }

//======// Main //================================================================================//

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);
	vec3 color = parameters.sampledColour.rgb * parameters.tinting.rgb;

	albedoOut = vec4(color, 1.0);

    // ivec2 screenTexel = ivec2(parameters.uv);
    // vec2 screenCoord = parameters.uv * viewPixelSize;
	// vec3 screenPos = vec3(screenCoord, loadDepthOpaqueLod(screenTexel));
	// vec3 viewPos = ScreenToViewSpaceRawVoxy(screenPos);
	// vec3 worldPos = transMAD(vxModelViewInv, viewPos);

	// Seems not needed for voxy /* Terrain noises */ {
	// 	const float res = 8.0;
	// 	const float strength = 0.25;

	// 	mat3 tbnMatrix = ConstructTBN(flatNormal);

	// 	vec2 coord = ((worldPos + cameraPosition) * tbnMatrix).xy * (res / 256.0);
	// 	float noise = texture(noisetex, coord).x * 2.0;

	// 	albedoOut.rgb = saturate(albedoOut.rgb * mix(1.0, noise, strength));
	// }

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = PackupDithered2x8U(parameters.lightMap, bayer4(parameters.uv));
	materialOut.y = uint(parameters.customId - 10000);
	materialOut.zw = uvec2(0);

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}