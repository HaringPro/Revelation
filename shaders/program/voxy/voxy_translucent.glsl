#include "/settings.glsl"

#define PASS_VOXY_WATER

//======// Utility //=============================================================================//

// #include "/lib/utility/Load.glsl"
#define loadDepthTransLod(texel) 	texelFetch(vxDepthTexTrans, texel, 0).x
#define loadDepthOpaqueLod(texel)	texelFetch(vxDepthTexOpaque, texel, 0).x

#include "/lib/utility/Math.glsl"
#include "/lib/utility/Pack.glsl"

//======// Output //==============================================================================//

layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;
layout (location = 2) out vec4 waterOut;

//======// Function //============================================================================//

// #include "/lib/universal/Transform.glsl"
vec3 ProjectDivide(in vec3 v, in mat4 m) {
	return projMAD(m, v) * rcp(m[2].w * v.z + m[3].w);
}
vec3 ScreenToViewSpaceRawVoxy(in vec3 screenPos) {
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	return ProjectDivide(NDCPos, vxProjInv);
}

// #include "/lib/universal/Random.glsl"
float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

//======// Main //================================================================================//
void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);
	vec4 vertColor = parameters.sampledColour * parameters.tinting;
	uint materialID = uint(parameters.customId - 10000);

	normalOut.xy = OctEncodeUnorm(flatNormal);

	if (materialID == 3u) { // water
		ivec2 texel = ivec2(parameters.uv);
    	vec2 screenCoord = parameters.uv * viewPixelSize;
		vec3 screenPos = vec3(screenCoord, loadDepthTransLod(texel));
		vec3 viewPos = ScreenToViewSpaceRawVoxy(screenPos);

		viewPos = viewPos - vxProj[3].yzw;

		vec3 worldPos = transMAD(vxModelViewInv, viewPos);


		float depthOpaque = loadDepthOpaqueLod(texel);
		vec3 viewPosOpaque = ScreenToViewSpaceRawVoxy(vec3(parameters.uv * viewPixelSize, depthOpaque));
		vec3 worldPosOpaque = transMAD(vxModelViewInv, viewPosOpaque);

		vec2 encodedNormal = normalOut.xy;
		normalOut.zw = encodedNormal;

		waterOut = vec4(distance(worldPos, worldPosOpaque) * r255, Packup2x8(encodedNormal), 0.0, 1.0);
	} else {
		normalOut.zw = normalOut.xy;

		materialOut.z = Packup2x8U(vertColor.xy);
		materialOut.w = Packup2x8U(vertColor.zw);
		waterOut = vec4(0.0);
	}

	materialOut.x = PackupDithered2x8U(parameters.lightMap, bayer4(parameters.uv));
	materialOut.y = materialID;
}