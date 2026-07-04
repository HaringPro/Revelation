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
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec4 materialOut;
layout(location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW
/* RENDERTARGETS: 6,7,8,12 */
layout(location = 3) out float parallaxOffsetOut;
#endif

//======// Input //===============================================================================//

flat in uint normalPack;
#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
flat in uint tangentPack;
#endif

in vec3 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	flat in vec2 tileScale;
	flat in vec2 tileOffset;

    #define localToAtlas(coord) (tileOffset + tileScale * fract(coord))
    #define atlasToLocal(coord) ((coord - tileOffset) * rcp(tileScale))
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

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
	#define loadAlbedo(uv) textureGrad(tex, localToAtlas(uv), deltaUv1, deltaUv2)

	vec3 AutoGenerateNormal(vec2 deltaUv1, vec2 deltaUv2) {
        vec2 localCoord = atlasToLocal(texCoord);
        vec2 quadSize = tileScale * vec2(atlasSize);
		vec2 bias = (16.0 / AGN_RESOLUTION) / quadSize;

		// Sample albedo
		vec4 sampleR = loadAlbedo(localCoord + vec2(bias.x, 0.0));
		vec4 sampleL = loadAlbedo(localCoord - vec2(bias.x, 0.0));
		vec4 sampleU = loadAlbedo(localCoord + vec2(0.0, bias.y));
		vec4 sampleD = loadAlbedo(localCoord - vec2(0.0, bias.y));

		// Evaluate heights from albedo luminance
		float heightR = luminance(sampleR.rgb * sampleR.a);
		float heightL = luminance(sampleL.rgb * sampleL.a);
		float heightU = luminance(sampleU.rgb * sampleU.a);
		float heightD = luminance(sampleD.rgb * sampleD.a);

		// Compute normal from height differences
		float deltaX = (heightL - heightR) * quadSize.x * AGN_STRENGTH;
		float deltaY = (heightD - heightU) * quadSize.y * AGN_STRENGTH;

		// Normalize
		return normalize(vec3(deltaX, deltaY, 32.0));
	}
#endif

//======// Main //================================================================================//
void main() {
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        if (any(greaterThanEqual(gl_FragCoord.xy, scaledViewSize))) {
            discard;
        }
    #endif

    vec2 deltaUv1 = dFdx(texCoord) * 0.5;
    vec2 deltaUv2 = dFdy(texCoord) * 0.5;

	float dither = BlueNoise(ivec2(gl_FragCoord.xy), frameCounter);

	normalOut.xy = unpackSnorm2x16(normalPack);
	vec3 geoNormal = OctDecodeSnorm(normalOut.xy);

	// Construct TBN matrix
	#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
		vec3 tangent = UnpackSnorm3x10(tangentPack);
		vec3 bitangent = cross(tangent, geoNormal);
        bitangent *= 1.0 - 2.0 * float(bitfieldExtract(tangentPack, 30, 1));
		mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);
	#endif

	vec3 viewPos = ScreenToViewPos(vec3(gl_FragCoord.xy * scaledTexelSize, gl_FragCoord.z));
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;

	vec2 realTexCoord = texCoord;

    #if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
        #ifdef AUTO_GENERATED_NORMAL
            vec3 tangentNormal = AutoGenerateNormal(deltaUv1, deltaUv2);
        #else
            vec3 tangentNormal = textureGrad(normals, realTexCoord, deltaUv1, deltaUv2).xyz;
            DecodeNormalTex(tangentNormal);
        #endif

        #ifdef PARALLAX
            #ifdef PARALLAX_SHADOW
                parallaxOffsetOut = 0.0;
            #endif

            vec2 localCoord = atlasToLocal(texCoord);
            float sampleHeight = SampleHeight(localCoord);

            float worldLengthSq = sdot(worldPos);
            float worldLengthInv = inversesqrt(worldLengthSq);
            float parallaxFade = smoothstep(64.0, 32.0, worldLengthSq * worldLengthInv);

            if (lessThanFLT1(sampleHeight) && parallaxFade > EPS) {
                vec3 tangentWorldPos = worldPos * tbnMatrix;
                vec3 tangentWorldDir = tangentWorldPos * worldLengthInv;
                vec3 localPos = CalculateParallax(localCoord, tangentWorldDir, dither, parallaxFade);
                realTexCoord = localToAtlas(localPos.xy);

                vec4 normalTex = textureGrad(normals, realTexCoord, deltaUv1, deltaUv2);
                tangentNormal = normalTex.xyz;
                DecodeNormalTex(tangentNormal);

                #ifdef PARALLAX_SHADOW
                    // Store offset between parallaxed screen depth and original depth
                    viewPos.z += viewPos.z / maxEps(-dot(worldPos, geoNormal)) * oms(localPos.z) * PARALLAX_DEPTH;
                    parallaxOffsetOut = ViewToScreenDepth(viewPos.z) - gl_FragCoord.z;
                #endif

                #ifdef PARALLAX_BASED_NORMAL
                if (normalTex.w > localPos.z + rcp255) {
                    tangentNormal = HeightBasedNormal(localPos.xy);
                }
                #endif
            }
        #endif

        vec3 normal = tbnMatrix * tangentNormal;
    #else
        vec3 normal = geoNormal;
    #endif

	vec4 albedo = textureGrad(tex, realTexCoord, deltaUv1, deltaUv2);

	if (albedo.a < alphaTestRef) discard;

	albedoOut = vec4(albedo.rgb * vertColor, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = Pack2x8U(lightmap, dither);
	materialOut.y = materialID;

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = textureGrad(specular, realTexCoord, deltaUv1, deltaUv2);
	#else
		vec4 specularTex = vec4(0.0);
	#endif

	// Compute rain puddles
	#ifdef RAIN_PUDDLES
		if (wetnessCustom > EPS) {
			ApplyRainPuddleMaterial(albedoOut.rgb, specularTex.rgb, worldPos, normal, geoNormal, lightmap.y);
		}
	#endif

	normalOut.zw = OctEncodeSnorm(normal);

	materialOut.z = Pack2x8U(specularTex.xy);
	materialOut.w = Pack2x8U(specularTex.zw);
}
