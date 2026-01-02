
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
/* RENDERTARGETS: 6,7,8,0 */
layout (location = 3) out float parallaxShadowOut;
#endif

//======// Input //===============================================================================//

#if defined NORMAL_MAPPING
	flat in mat3 tbnMatrix;
	#define flatNormal tbnMatrix[2]
#else
	flat in vec3 flatNormal;
#endif

in vec3 vertColor;
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

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

#ifdef PARALLAX
	#include "/lib/universal/Transform.glsl"
	#include "/lib/surface/Parallax.glsl"
#endif

#ifdef AUTO_GENERATED_NORMAL
	vec2 serializeCoord(in vec2 uv) {
		return mix(1.0 - fract(uv), fract(uv), mod(floor(uv), 2.0));
	}

	#define loadAlbedo(uv) texture(tex, tileOffset + tileScale * serializeCoord(uv))

	vec3 AutoGenerateNormal() {
		vec2 bias = (4.0 / AGN_RESOLUTION) / tileScale;

		// Sample albedo
		vec4 sampleR = loadAlbedo(tileBase + vec2(bias.x, 0.0));
		vec4 sampleL = loadAlbedo(tileBase - vec2(bias.x, 0.0));
		vec4 sampleU = loadAlbedo(tileBase + vec2(0.0, bias.y));
		vec4 sampleD = loadAlbedo(tileBase - vec2(0.0, bias.y));

		// Get heights from albedo luminance
		float heightR = luminance(sampleR.rgb * sampleR.a);
		float heightL = luminance(sampleL.rgb * sampleL.a);
		float heightU = luminance(sampleU.rgb * sampleU.a);
		float heightD = luminance(sampleD.rgb * sampleD.a);

		// Get normal from height differences
		float deltaX = (heightL - heightR) * AGN_STRENGTH;
		float deltaY = (heightD - heightU) * AGN_STRENGTH;

		// Normalize normal
		return normalize(vec3(deltaX, deltaY, 0.75));
	}
#endif

//======// Main //================================================================================//
void main() {
	float dither = BlueNoise(ivec2(gl_FragCoord.xy), frameCounter);

	#ifdef PARALLAX
		#define ReadTexture(tex) textureGrad(tex, parallaxCoord, texGrad[0], texGrad[1])

		mat2 texGrad = mat2(dFdx(texCoord), dFdy(texCoord));

		vec2 parallaxCoord = texCoord;

		vec4 normalTex = ReadTexture(normals);

		#ifdef PARALLAX_DEPTH_WRITE
			gl_FragDepth = gl_FragCoord.z;
		#endif

		if (normalTex.w < (1.0 - r255)) {
			float tangentViewLength = length(tangentViewPos);
			float parallaxFade = smoothstep(64.0, 32.0, tangentViewLength);

			vec3 offsetCoord = CalculateParallax(tangentViewPos / tangentViewLength, dither, parallaxFade);
			parallaxCoord = atlasCoord(offsetCoord.xy);

			normalTex = ReadTexture(normals);

			DecodeNormalTex(normalTex.xyz);

			if (offsetCoord.z < (1.0 - r255) && parallaxFade > EPS) {
				#ifdef PARALLAX_DEPTH_WRITE
					gl_FragDepth = ViewToScreenDepth(ScreenToViewDepth(gl_FragDepth) - oms(offsetCoord.z) * PARALLAX_DEPTH);
				#elif defined PARALLAX_SHADOW
					if (dot(tbnMatrix[2], worldLightVector) > 1e-3) {
						parallaxShadowOut = CalculateParallaxShadow(worldLightVector * tbnMatrix, offsetCoord, dither, parallaxFade);
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

		normalOut.zw = OctEncodeUnorm(tbnMatrix * normalTex.xyz);
	#else
		#define ReadTexture(tex) texture(tex, texCoord)

		#if defined NORMAL_MAPPING
			#ifdef AUTO_GENERATED_NORMAL
				vec3 normalTex = AutoGenerateNormal();
			#else
				vec3 normalTex = ReadTexture(normals).xyz;
				DecodeNormalTex(normalTex);
			#endif

			normalOut.zw = OctEncodeUnorm(tbnMatrix * normalTex);
		#else
			normalOut.zw = OctEncodeUnorm(flatNormal);
		#endif
	#endif

	vec4 albedo = ReadTexture(tex);

	if (albedo.a < 0.1) { discard; return; }

	albedoOut = vec4(albedo.rgb * vertColor, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	normalOut.xy = OctEncodeUnorm(flatNormal);

	materialOut.x = PackupDithered2x8U(lightmap, dither);
	materialOut.y = materialID;

	#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
		vec4 specularTex = ReadTexture(specular);
		materialOut.z = Packup2x8U(specularTex.xy);
		materialOut.w = Packup2x8U(specularTex.zw);
	#endif
}