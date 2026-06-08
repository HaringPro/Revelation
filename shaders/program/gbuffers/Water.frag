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

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

//======// Main //================================================================================//
void main() {
	// Construct TBN matrix
	vec3 deltaPos1 = dFdx(worldPos);
	vec3 deltaPos2 = dFdy(worldPos);

	vec3 geoNormal = normalize(cross(deltaPos1, deltaPos2));
    normalOut.xy = OctEncodeSnorm(geoNormal);

    vec3 deltaPos1Perp = cross(geoNormal, deltaPos1);
    vec3 deltaPos2Perp = cross(deltaPos2, geoNormal);

    vec2 deltaUv1 = dFdx(texCoord);
    vec2 deltaUv2 = dFdy(texCoord);

    vec3 tangent   = normalize(deltaPos2Perp * deltaUv1.x + deltaPos1Perp * deltaUv2.x);
    vec3 bitangent = normalize(deltaPos2Perp * deltaUv1.y + deltaPos1Perp * deltaUv2.y);

    float invmax = inversesqrt(max(sdot(tangent), sdot(bitangent)));
    mat3 tbnMatrix = mat3(tangent * invmax, bitangent * invmax, geoNormal);

	if (materialID == 3u) { // water
		ivec2 texelPos = ivec2(gl_FragCoord.xy);
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

        // Apply rain ripples
		if (rainStrength > EPS) {
            vec2 rippleSlope = RippleSlope(minecraftPos.xz * RIPPLE_SCALE, frameTimeCounter);
            rippleSlope *= saturate(4.0 * abs(dot(geoNormal, worldDir))) * saturate(lightmap.y * 5.0 - 4.0) * 0.25;
            worldNormal = normalize(worldNormal + vec3(rippleSlope * rainStrength, 0.0).xzy);
        }

		float depth1 = loadDepth1(texelPos);
		vec3 viewPos1 = ScreenToViewPos(vec3(gl_FragCoord.xy * scaledTexelSize, depth1));
		vec3 worldPos1 = transMAD(gbufferModelViewInverse, viewPos1);

		vec2 encodedNormal = OctEncodeSnorm(worldNormal);
		normalOut.zw = encodedNormal;

		waterOut = vec4(distance(worldPos, worldPos1) * rcp255, Pack2x8(encodedNormal), 0.0, 1.0);
	} else {
		vec4 albedo = texture(tex, texCoord) * vertColor;

		if (albedo.a < 0.1) { discard; return; }

		#if defined MC_NORMAL_MAP
			vec3 normalTex = texture(normals, texCoord).rgb;
			DecodeNormalTex(normalTex);
			vec3 worldNormal = tbnMatrix * normalTex;
		#else
            vec3 worldNormal = geoNormal;
		#endif

        // Apply rain ripples
		if (rainStrength > EPS) {
			vec3 minecraftPos = worldPos + cameraPosition;
		    vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

            vec2 rippleSlope = RippleSlope(minecraftPos.xz * RIPPLE_SCALE, frameTimeCounter);
            rippleSlope *= saturate(4.0 * abs(dot(geoNormal, worldDir))) * saturate(lightmap.y * 5.0 - 4.0);
            worldNormal = normalize(worldNormal + vec3(rippleSlope * rainStrength, 0.0).xzy);
        }

		normalOut.zw = OctEncodeSnorm(worldNormal);

		materialOut.z = Pack2x8U(albedo.xy);
		materialOut.w = Pack2x8U(albedo.zw);
		waterOut = vec4(0.0);
	}

	materialOut.x = Pack2x8U(lightmap, bayer4(gl_FragCoord.xy));
	materialOut.y = materialID;
}
