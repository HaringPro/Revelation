
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

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

float R1(in int n, in float seed) {
    const float g = 1.6180339887498948482;
    const float a = 1.0 / g;
	return fract(seed + n * a);
}
float BlueNoise(in ivec2 texel, in int frame) {
	#ifdef TAA_ENABLED
		return R1(frame, texelFetch(noisetex, texel & 255, 0).a);
	#else
		return texelFetch(noisetex, texel & 255, 0).a;
	#endif
}

//======// Main //================================================================================//

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	ivec2 texel = ivec2(parameters.uv);
    vec2 screenCoord = parameters.uv * viewPixelSize;
	float depth = loadDepth1Lod(texel);
	vec3 viewPos = ScreenToViewSpaceRawVoxy(vec3(screenCoord, depth));
	vec3 worldPos = transMAD(vxModelViewInv, viewPos);

    float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), sdot(worldPos));
	float dither = BlueNoise(texel, frameCounter);

    if (alpha < dither || loadDepth0Lod(texel) < 1.0) {
        discard;
        return;
    }

	vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);
	vec3 color = parameters.sampledColour.rgb * parameters.tinting.rgb;

	albedoOut = vec4(color, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = Packup2x8U(saturate((parameters.lightMap - 0.03125) * 1.06667));
	materialOut.y = uint(parameters.customId - 10000);
	materialOut.zw = uvec2(0);

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}