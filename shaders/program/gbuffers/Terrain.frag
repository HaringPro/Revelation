
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

in vec3 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	in vec2 tileBase;
	flat in vec2 tileScale;
	flat in vec2 tileOffset;

	in vec3 tangentViewPos;
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
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

#ifdef AUTO_GENERATED_NORMAL
	vec2 serializeCoord(in vec2 uv) {
		return mix(1.0 - fract(uv), fract(uv), mod(floor(uv), 2.0));
	}

	#define sampleAlbedo(uv) texture(tex, tileOffset + tileScale * serializeCoord(uv))

	vec3 AutoGenerateNormal() {
		vec2 bias = (4.0 / AGN_RESOLUTION) / tileScale;

		// Sample albedo
		vec4 sampleR = sampleAlbedo(tileBase + vec2(bias.x, 0.0));
		vec4 sampleL = sampleAlbedo(tileBase - vec2(bias.x, 0.0));
		vec4 sampleU = sampleAlbedo(tileBase + vec2(0.0, bias.y));
		vec4 sampleD = sampleAlbedo(tileBase - vec2(0.0, bias.y));

		// Get heights from albedo luminance
		float heightR = GetLuminance(sampleR.rgb * sampleR.a);
		float heightL = GetLuminance(sampleL.rgb * sampleL.a);
		float heightU = GetLuminance(sampleU.rgb * sampleU.a);
		float heightD = GetLuminance(sampleD.rgb * sampleD.a);

		// Get normal from height differences
		float deltaX = (heightL - heightR) * AGN_STRENGTH;
		float deltaY = (heightD - heightU) * AGN_STRENGTH;

		// Normalize normal
		return normalize(vec3(deltaX, deltaY, 0.75));
	}
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
			vec2 texSize = vec2(atlasSize);
			float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
			float parallaxFade = exp2(-0.1 * max0(length(tangentViewPos) - 2.0));

			vec3 offsetCoord = CalculateParallax(normalize(tangentViewPos), texSize, dither);
			parallaxCoord = OffsetCoord(offsetCoord.xy);

			normalTex = ReadTexture(normals);

			DecodeNormalTex(normalTex.xyz);

			if (offsetCoord.z < 0.999 && parallaxFade > 1e-5) {
				#ifdef PARALLAX_DEPTH_WRITE
					gl_FragDepth = ViewToScreenDepth(ScreenToViewDepth(gl_FragDepth) + oneMinus(offsetCoord.z) * PARALLAX_DEPTH);
				#elif defined PARALLAX_SHADOW
					if (dot(tbnMatrix[2], worldLightVector) > 1e-3) {
						gbufferOut1.z = CalculateParallaxShadow(worldLightVector * tbnMatrix, offsetCoord, texSize, dither) * parallaxFade;
					}
				#endif
				#ifdef PARALLAX_BASED_NORMAL
					#define sampleHeight(uv) textureGrad(normals, OffsetCoord(uv), texGrad[0], texGrad[1]).w

					vec2 bias = 1e-2 * tileScale;
					float heightR = sampleHeight(offsetCoord.xy + vec2(bias.x, 0.0));
					float heightL = sampleHeight(offsetCoord.xy - vec2(bias.x, 0.0));
					float heightU = sampleHeight(offsetCoord.xy + vec2(0.0, bias.y));
					float heightD = sampleHeight(offsetCoord.xy - vec2(0.0, bias.y));

					float deltaX = (heightL - heightR) * 2.0;
					float deltaY = (heightD - heightU) * 2.0;

					vec3 pbN = vec3(deltaX, deltaY, step(abs(deltaX) + abs(deltaY), 1e-3));
					normalTex.xyz = mix(normalTex.xyz, pbN, parallaxFade * oneMinus(pbN.z));
				#endif
			}
		} else {
			DecodeNormalTex(normalTex.xyz);
		}

		gbufferOut0.w = packUnorm2x8(encodeUnitVector(tbnMatrix * normalTex.xyz));
	#else
		#define ReadTexture(tex) texture(tex, texCoord)

		#if defined NORMAL_MAPPING
			#ifdef AUTO_GENERATED_NORMAL
				vec3 normalTex = AutoGenerateNormal();
			#else
				vec3 normalTex = ReadTexture(normals).xyz;
				DecodeNormalTex(normalTex);
			#endif
			gbufferOut0.w = packUnorm2x8(encodeUnitVector(tbnMatrix * normalTex));
		#endif
	#endif

	vec4 albedo = ReadTexture(tex);

	if (albedo.a < 0.1) { discard; return; }

	albedoOut = albedo.rgb * tint;

	#ifdef WHITE_WORLD
		albedoOut = vec3(1.0);
	#endif

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID) * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(tbnMatrix[2]));
	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 specularTex = ReadTexture(specular);

		gbufferOut1.x = packUnorm2x8(specularTex.rg);
		gbufferOut1.y = packUnorm2x8(specularTex.ba);
	#endif
}