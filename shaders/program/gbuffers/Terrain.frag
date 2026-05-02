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

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
/* RENDERTARGETS: 6,7,8,12 */
layout (location = 3) out float parallaxShadowOut;
#endif

//======// Input //===============================================================================//

flat in uint normalPack;
#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
flat in uvec2 tangentPack;
#endif

in vec3 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	in vec2 tileBase;
	flat in vec2 tileScale;
	flat in vec2 tileOffset;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined MC_NORMAL_MAP
	uniform sampler2D normals;
#endif

#if defined MC_SPECULAR_MAP
	uniform sampler2D specular;
#endif

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"
#include "/lib/universal/Transform.glsl"

#ifdef PARALLAX
	#include "/lib/surface/Parallax.glsl"
#endif

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

#ifdef AUTO_GENERATED_NORMAL
	#define loadAlbedo(uv, mipLevel) textureLod(tex, tileOffset + tileScale * fract(uv), mipLevel)

	vec3 AutoGenerateNormal(float mipLevel) {
		vec2 bias = (16.0 / AGN_RESOLUTION) / (tileScale * vec2(atlasSize));

		// Sample albedo
		vec4 sampleR = loadAlbedo(tileBase + vec2(bias.x, 0.0), mipLevel);
		vec4 sampleL = loadAlbedo(tileBase - vec2(bias.x, 0.0), mipLevel);
		vec4 sampleU = loadAlbedo(tileBase + vec2(0.0, bias.y), mipLevel);
		vec4 sampleD = loadAlbedo(tileBase - vec2(0.0, bias.y), mipLevel);

		// Evaluate heights from albedo luminance
		float heightR = luminance(sampleR.rgb * sampleR.a);
		float heightL = luminance(sampleL.rgb * sampleL.a);
		float heightU = luminance(sampleU.rgb * sampleU.a);
		float heightD = luminance(sampleD.rgb * sampleD.a);

		// Compute normal from height differences
		float deltaX = (heightL - heightR) * AGN_STRENGTH;
		float deltaY = (heightD - heightU) * AGN_STRENGTH;

		// Normalize normal
		return normalize(vec3(deltaX, deltaY, 32.0 / AGN_RESOLUTION));
	}
#endif

//======// Main //================================================================================//
void main() {
	float dither = BlueNoise(ivec2(gl_FragCoord.xy), frameCounter);

	normalOut.xy = unpackSnorm2x16(normalPack);
	vec3 geoNormal = OctDecodeSnorm(normalOut.xy);

	// Construct TBN matrix
	#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
		vec3 tangent = OctDecodeSnorm(unpackSnorm2x16(tangentPack.x));
		vec3 bitangent = cross(tangent, geoNormal) * uintBitsToFloat(tangentPack.y);
		mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);
	#endif

	vec3 viewPos = ScreenToViewPos(vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z));
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;

	// Compute mipmap level
	#if RENDER_MODE == 1
		float mipLevel = 0.5 * log2(maxOf(fwidth(texCoord * vec2(atlasSize))));
	#else
		const float mipLevel = 0.0;
	#endif

	vec2 realTexCoord = texCoord;

	#ifdef PARALLAX
		vec4 normalTex = textureLod(normals, realTexCoord, mipLevel);

		#ifdef PARALLAX_DEPTH_WRITE
			gl_FragDepth = gl_FragCoord.z;
		#endif

		if (normalTex.w < (1.0 - rcp255)) {
			vec3 tangentPos = worldPos * tbnMatrix;

			float worldLength = length(worldPos);
			float parallaxFade = smoothstep(64.0, 32.0, worldLength);

			vec3 offsetCoord = CalculateParallax(tangentPos / worldLength, dither, parallaxFade);
			realTexCoord = atlasCoord(offsetCoord.xy);

			normalTex = textureLod(normals, realTexCoord, mipLevel);
			DecodeNormalTex(normalTex.xyz);

			if (offsetCoord.z < (1.0 - rcp255) && parallaxFade > EPS) {
				#ifdef PARALLAX_DEPTH_WRITE
					gl_FragDepth = ViewToScreenDepth(ScreenToViewDepth(gl_FragDepth) - oms(offsetCoord.z) * PARALLAX_DEPTH);
				#elif defined PARALLAX_SHADOW
					if (dot(tbnMatrix[2], worldLightDir) > 1e-3) {
						parallaxShadowOut = CalculateParallaxShadow(worldLightDir * tbnMatrix, offsetCoord, dither, parallaxFade);
					}
				#endif
				#ifdef PARALLAX_BASED_NORMAL
					#define sampleHeight(uv) textureGrad(normals, atlasCoord(uv), texGrad[0], texGrad[1]).w

					vec2 bias = 1e-2 / (tileScale * vec2(atlasSize));
					float heightR = sampleHeight(offsetCoord.xy + vec2(bias.x, 0.0));
					float heightL = sampleHeight(offsetCoord.xy - vec2(bias.x, 0.0));
					float heightU = sampleHeight(offsetCoord.xy + vec2(0.0, bias.y));
					float heightD = sampleHeight(offsetCoord.xy - vec2(0.0, bias.y));

					float deltaX = heightL - heightR;
					float deltaY = heightD - heightU;

					normalTex.xyz = normalize(vec3(deltaX, deltaY, step(abs(deltaX) + abs(deltaY), 1e-3)));
				#endif
			}
		} else {
			DecodeNormalTex(normalTex.xyz);
		}

		vec3 normal = tbnMatrix * normalTex.xyz;
	#else
		#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
			#ifdef AUTO_GENERATED_NORMAL
				vec3 normalTex = AutoGenerateNormal(mipLevel);
			#else
				vec3 normalTex = textureLod(normals, realTexCoord, mipLevel).xyz;
				DecodeNormalTex(normalTex);
			#endif

			vec3 normal = tbnMatrix * normalTex;
		#else
			vec3 normal = geoNormal;
		#endif
	#endif

	vec4 albedo = textureLod(tex, realTexCoord, mipLevel);

	if (albedo.a < 0.1) { discard; return; }

	albedoOut = vec4(albedo.rgb * vertColor, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = PackupDithered2x8U(lightmap, dither);
	materialOut.y = materialID;

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = textureLod(specular, realTexCoord, 0.0);
	#else
		vec4 specularTex = vec4(0.0);
	#endif

	// Compute rain puddles
	#ifdef RAIN_PUDDLES
		if (wetnessCustom > EPS) {
			CalculateRainPuddles(albedoOut.rgb, specularTex.rgb, worldPos, normal, geoNormal, lightmap.y);
		}
	#endif

	normalOut.zw = OctEncodeSnorm(normal);

	materialOut.z = Packup2x8U(specularTex.xy);
	materialOut.w = Packup2x8U(specularTex.zw);
}
