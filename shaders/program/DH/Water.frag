
#define PASS_DH_WATER

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 7,8,12 */
layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;
layout (location = 2) out vec4 waterOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Input //===============================================================================//

flat in vec3 flatNormal;

in vec4 vertColor;
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
	ivec2 texel = ivec2(gl_FragCoord.xy);
    float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), sdot(worldPos));
	float dither = BlueNoise(texel, frameCounter);

    if (alpha < dither || loadDepth0(texel) < 1.0) {
        discard;
        return;
    }

	normalOut.xy = OctEncodeUnorm(flatNormal);

	if (materialID == 3u) { // water
		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			vec3 worldNormal = wave.normal;
		#else
			const mat3 tbnMatrix = mat3(
				vec3(1.0, 0.0, 0.0),
				vec3(0.0, 0.0, 1.0),
				vec3(0.0, 1.0, 0.0)
			);

			vec3 minecraftPos = worldPos + cameraPosition;
			#ifdef WATER_PARALLAX
				vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
			#else
				vec3 worldNormal = CalculateWaterNormal(minecraftPos);
			#endif

			worldNormal = tbnMatrix * worldNormal;
		#endif

		float depth1 = loadDepth1Lod(texel);
		vec3 viewPos1 = ScreenToViewSpace(vec3(gl_FragCoord.xy * viewPixelSize, depth1));
		vec3 worldPos1 = transMAD(gbufferModelViewInverse, viewPos1);

		vec2 encodedNormal = OctEncodeUnorm(worldNormal);
		normalOut.zw = encodedNormal;

		waterOut = vec4(distance(worldPos, worldPos1) * r255, Packup2x8(encodedNormal), 0.0, 1.0);
	} else {
		normalOut.zw = normalOut.xy;

		materialOut.z = Packup2x8U(vertColor.xy);
		materialOut.w = Packup2x8U(vertColor.zw);
		waterOut = vec4(0.0);
	}

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = materialID;
}