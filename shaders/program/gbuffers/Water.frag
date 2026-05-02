/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 7,8,12 */
layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;
layout (location = 2) out vec4 waterOut;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined MC_NORMAL_MAP
	uniform sampler2D normals;
#endif

#if defined MC_SPECULAR_MAP
	uniform sampler2D specular;
#endif

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Input //===============================================================================//

flat in uint normalPack;
flat in uvec2 tangentPack;

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 worldPos;

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Random.glsl"

#define PHYSICS_OCEAN_SUPPORT

#ifdef PHYSICS_OCEAN
	#define PHYSICS_FRAGMENT
	#include "/lib/water/PhysicsOceans.glsl"
#else
	#include "/lib/water/WaterWave.glsl"
#endif

//======// Main //================================================================================//
void main() {
	normalOut.xy = unpackSnorm2x16(normalPack);

	// Construct TBN matrix
	vec3 tangent = OctDecodeSnorm(unpackSnorm2x16(tangentPack.x));
	vec3 normal = OctDecodeSnorm(normalOut.xy);
	vec3 bitangent = cross(tangent, normal) * uintBitsToFloat(tangentPack.y);
	mat3 tbnMatrix = mat3(tangent, bitangent, normal);

	if (materialID == 3u) { // water
		ivec2 texel = ivec2(gl_FragCoord.xy);
		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			vec3 worldNormal = wave.normal;
		#else
			vec3 minecraftPos = worldPos + cameraPosition;
			#ifdef WATER_PARALLAX
				vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
			#else
				vec3 worldNormal = CalculateWaterNormal(minecraftPos);
			#endif

			worldNormal = tbnMatrix * worldNormal;
		#endif

		float depth1 = loadDepth1(texel);
		vec3 viewPos1 = ScreenToViewPos(vec3(gl_FragCoord.xy * viewPixelSize, depth1));
		vec3 worldPos1 = transMAD(gbufferModelViewInverse, viewPos1);

		vec2 encodedNormal = OctEncodeSnorm(worldNormal);
		normalOut.zw = encodedNormal;

		waterOut = vec4(distance(worldPos, worldPos1) * rcp255, Packup2x8(encodedNormal), 0.0, 1.0);
	} else {
		vec4 albedo = texture(tex, texCoord) * vertColor;

		if (albedo.a < 0.1) { discard; return; }

		#if defined MC_NORMAL_MAP
			vec3 normalTex = texture(normals, texCoord).rgb;
			DecodeNormalTex(normalTex);
			normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
		#else
			normalOut.zw = normalOut.xy;
		#endif

		materialOut.z = Packup2x8U(albedo.xy);
		materialOut.w = Packup2x8U(albedo.zw);
		waterOut = vec4(0.0);
	}

	materialOut.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	materialOut.y = materialID;
}
