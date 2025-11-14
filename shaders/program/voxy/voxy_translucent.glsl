#include "/settings.glsl"

// #define PASS_DH_WATER

//======// Utility //=============================================================================//

// #include "/lib/utility/Load.glsl"
#define loadDepth0(texel) 			texelFetch(depthtex0, texel, 0).x
#include "/lib/utility/Math.glsl"
#include "/lib/utility/Pack.glsl"

//======// Output //==============================================================================//

layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;
layout (location = 2) out vec4 waterOut;

//======// SSBO //================================================================================//

// #include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

// #include "/lib/universal/Transform.glsl"
// #include "/lib/universal/Random.glsl"
float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

// #define PHYSICS_OCEAN_SUPPORT

// #ifdef PHYSICS_OCEAN
// 	#define PHYSICS_FRAGMENT
// 	#include "/lib/water/PhysicsOceans.glsl"
// #else
// 	#include "/lib/water/WaterWave.glsl"
// #endif

//======// Main //================================================================================//
void voxy_emitFragment(VoxyFragmentParameters parameters) {
	ivec2 texel = ivec2(parameters.uv);
	// if (loadDepth0(texel) < 1.0) { discard; return; }

	vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);
	vec4 vertColor = parameters.sampledColour * parameters.tinting;
	uint materialID = uint(parameters.customId - 10000) == 3u ? 3u : 2u;

	normalOut.xy = OctEncodeUnorm(flatNormal);

// 	if (materialID == 3u) { // water
// 		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

// 		#ifdef PHYSICS_OCEAN
// 			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

// 			vec3 worldNormal = wave.normal;
// 		#else
// 			const mat3 tbnMatrix = mat3(
// 				vec3(1.0, 0.0, 0.0),
// 				vec3(0.0, 0.0, 1.0),
// 				vec3(0.0, 1.0, 0.0)
// 			);

// 			vec3 minecraftPos = worldPos + cameraPosition;
// 			#ifdef WATER_PARALLAX
// 				vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
// 			#else
// 				vec3 worldNormal = CalculateWaterNormal(minecraftPos);
// 			#endif

// 			worldNormal = tbnMatrix * worldNormal;
// 		#endif

// 		float depth1 = loadDepthOpaqueLod(texel);
// 		vec3 viewPos1 = ScreenToViewSpace(vec3(gl_FragCoord.xy * viewPixelSize, depth1));
// 		vec3 worldPos1 = transMAD(gbufferModelViewInverse, viewPos1);

// 		vec2 encodedNormal = OctEncodeUnorm(worldNormal);
// 		normalOut.zw = encodedNormal;

// 		waterOut = vec4(distance(worldPos, worldPos1) * r255, Packup2x8(encodedNormal), 0.0, 1.0);
// 	} else {
		normalOut.zw = normalOut.xy;

		materialOut.z = Packup2x8U(vertColor.xy);
		materialOut.w = Packup2x8U(vertColor.zw);
		waterOut = vec4(0.0);
// 	}

	materialOut.x = PackupDithered2x8U(parameters.lightMap, bayer4(parameters.uv));
	materialOut.y = materialID;
}