
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7 */
layout (location = 0) out vec3 albedoOut;
layout (location = 1) out vec4 gbufferOut0;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec3 gbufferOut1;
#elif defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
/* RENDERTARGETS: 6,7,8 */
layout (location = 2) out vec2 gbufferOut1;
#endif

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

#if defined PARALLAX
	in vec2 tileCoord;
	flat in vec2 tileScale;
	flat in vec2 tileOffset;

	in vec3 tangentViewDir;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

#if defined PARALLAX
	uniform mat4 gbufferModelView;
	uniform mat4 gbufferProjection;

	uniform vec3 worldLightVector;
	uniform int frameCounter;
#endif

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

#ifdef PARALLAX
	float InterleavedGradientNoiseTemporal(in vec2 coord) {
		return fract(52.9829189 * fract(0.06711056 * coord.x + 0.00583715 * coord.y + 0.00623715 * (frameCounter & 63)));
	}

	float ScreenToViewDepth(in float depth) {
		return gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
	}

	float ViewToScreenDepth(in float depth) {
		return (gbufferProjection[3].z - gbufferProjection[2].z * depth) / depth * 0.5 + 0.5;
	}

	#include "/lib/surface/Parallax.glsl"
#endif

//======// Main //================================================================================//
void main() {
	#ifdef PARALLAX
		#define ReadTexture(tex) textureGrad(tex, parallaxCoord, texGrad[0], texGrad[1])

		mat2 texGrad = mat2(dFdx(texCoord), dFdy(texCoord));

		vec2 parallaxCoord = texCoord;

		vec4 normalTex = ReadTexture(normals);

		#ifdef PARALLAX_DEPTH_WRITE
			gl_FragDepth = gl_FragCoord.z;
		#endif

		if (normalTex.w < 0.999) {
			float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
			vec3 offsetCoord = CalculateParallax(tangentViewDir, texGrad, dither);
			parallaxCoord = OffsetCoord(offsetCoord.xy);

			normalTex = ReadTexture(normals);

			DecodeNormalTex(normalTex.xyz);

			if (offsetCoord.z < 0.999) {
				#ifdef PARALLAX_DEPTH_WRITE
					gl_FragDepth = ViewToScreenDepth(ScreenToViewDepth(gl_FragDepth) + oneMinus(offsetCoord.z) * PARALLAX_DEPTH);
				#elif defined PARALLAX_SHADOW
					if (dot(tbnMatrix[2], worldLightVector) > 1e-3) {
						gbufferOut1.z = CalculateParallaxShadow(worldLightVector * tbnMatrix, offsetCoord, texGrad, dither);
					}
				#endif
				#ifdef PARALLAX_BASED_NORMAL
					// Parallax-based normal from GeForceLegend
					vec2 bias = 1e-2 * tileScale;
					float rD = textureGrad(normals, OffsetCoord(offsetCoord.xy + vec2(bias.x, 0.0)), texGrad[0], texGrad[1]).w;
					float lD = textureGrad(normals, OffsetCoord(offsetCoord.xy - vec2(bias.x, 0.0)), texGrad[0], texGrad[1]).w;
					float uD = textureGrad(normals, OffsetCoord(offsetCoord.xy + vec2(0.0, bias.y)), texGrad[0], texGrad[1]).w;
					float dD = textureGrad(normals, OffsetCoord(offsetCoord.xy - vec2(0.0, bias.y)), texGrad[0], texGrad[1]).w;
					normalTex.xyz = vec3((lD - rD), (dD - uD), step(abs(lD - rD) + abs(dD - uD), 1e-3));
				#endif
			}
		} else {
			DecodeNormalTex(normalTex.xyz);
		}

		gbufferOut0.w = packUnorm2x8(encodeUnitVector(tbnMatrix * normalTex.xyz));
	#else
		#define ReadTexture(tex) texture(tex, texCoord)

		#if defined NORMAL_MAPPING
			vec3 normalTex = ReadTexture(normals).xyz;
			DecodeNormalTex(normalTex);
			gbufferOut0.w = packUnorm2x8(encodeUnitVector(tbnMatrix * normalTex));
		#endif
	#endif

	vec4 albedo = ReadTexture(tex) * tint;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	albedoOut = albedo.rgb;

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(tbnMatrix[2]));
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 specularTex = ReadTexture(specular);

		gbufferOut1.x = packUnorm2x8(specularTex.rg);
		gbufferOut1.y = packUnorm2x8(specularTex.ba);
	#endif
}