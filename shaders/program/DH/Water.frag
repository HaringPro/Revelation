/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

#define PASS_DH_WATER

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7,8,12 */
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec2 materialOut;
layout(location = 2) out vec4 normalOut;
layout(location = 3) out vec4 waterOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Input //===============================================================================//

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
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), sdot(worldPos));
	float dither = BlueNoise(texelPos, frameCounter);

	if (alpha < dither || lessThanFLT1(loadDepth0(texelPos))) {
		discard;
		return;
	}

	vec3 geoNormal = normalize(cross(dFdx(worldPos), dFdy(worldPos)));
	normalOut.xy = OctEncodeSnorm(geoNormal);

	if (materialID == 3u) { // water
		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			vec3 worldNormal = wave.normal;
		#else
			mat3 tbnMatrix = BuildOrthonormalBasis(geoNormal);

			vec3 minecraftPos = worldPos + cameraPosition;
			#ifdef WATER_PARALLAX
				vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
			#else
				vec3 worldNormal = CalculateWaterNormal(minecraftPos);
			#endif

			worldNormal = tbnMatrix * worldNormal;
		#endif

		float depthBack = loadDepth1Lod(texelPos);
		vec3 viewPosBack = ScreenToViewPosLod(vec3(gl_FragCoord.xy * scaledTexelSize, depthBack));
		vec3 worldPosBack = transMAD(gbufferModelViewInverse, viewPosBack);

		vec2 encodedNormal = OctEncodeSnorm(worldNormal);
		normalOut.zw = encodedNormal;

        float waterDepth = distance(worldPos, worldPosBack) * rcp255;
		waterOut = vec4(waterDepth, Pack2x8(encodedNormal * 0.5 + 0.5), 0.0, 1.0);
	} else {
		normalOut.zw = normalOut.xy;
        albedoOut = vertColor;
        #ifdef DISTANT_HORIZONS_TEXTURES
            if (dh_hasTexture()) {
                vec4 albedo = dh_sampleTexture();
                vec3 clampedColor = saturate(albedoOut.rgb * (albedo.rgb * 2.0));
                albedoOut.rgb = mix(albedoOut.rgb, clampedColor, albedo.a);
            }
        #endif
		waterOut = vec4(0.0);
	}

	materialOut.x = Pack2x8U(lightmap);
	materialOut.y = materialID;
}
