
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,7,8 */
layout (location = 0) out vec4 sceneOut;
layout (location = 1) out vec4 gbufferOut0;
layout (location = 2) out vec4 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

#include "/lib/utility/Uniform.glsl"

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 worldPos;
in vec4 viewPos;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Function //============================================================================//

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"

#include "/lib/atmospherics/Global.inc"

#include "/lib/water/WaterWave.glsl"
// #include "/lib/water/WaterFog.glsl"

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 viewPos) {
	skylight = smoothstep(0.3, 0.8, cube(skylight));
	vec3 viewDir = normalize(viewPos);
	normal = mat3(gbufferModelView) * normal;

	float LdotH = dot(normal, -viewDir);
	vec3 rayDir = viewDir + normal * LdotH * 2.0;

	float NdotL = dot(normal, rayDir);
	if (NdotL < 1e-6) return vec4(0.0);

	vec3 reflection;
	if (skylight > 1e-3) {
		if (isEyeInWater == 0) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld) + vec2(0.0, 0.5)).rgb;

			reflection = skyRadiance * skylight;
		// } else /* if (materialID == 3u)  */{
		// 	reflection = skyIlluminance * 5e-3 / (vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B) + 1e-2);
		}
	}

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z);

	bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
		reflection += (texelFetch(colortex4, rawCoord(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade * 8e2);
	}

	float NdotV = max(1e-6, dot(normal, -viewDir));
	float brdf;
	if (isEyeInWater == 1) { // Total internal reflection
		//specular = FresnelDielectricN(NdotV, 1.000293 / WATER_REFRACT_IOR);
		brdf = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
	} else {
		brdf = FresnelDielectricN(NdotV, /* materialID == 3u ? WATER_REFRACT_IOR : GLASS_REFRACT_IOR */WATER_REFRACT_IOR);
	}

	return vec4(reflection * brdf, brdf);
}

//======// Main //================================================================================//
void main() {
	vec3 worldNormal;
	vec4 albedo;
	if (materialID == 3u) { // water
		vec3 minecraftPos = worldPos + cameraPosition;
		#ifdef WATER_PARALLAX
			worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y, normalize(worldPos - gbufferModelViewInverse[3].xyz) * tbnMatrix);
		#else
			worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
		#endif

		gbufferOut1.x = packUnorm2x8(worldNormal.xy * 0.5 + 0.5);
		// albedo = sceneOut = vec4(0.0, 0.0, 0.0, 1e-2);

		worldNormal = tbnMatrix * worldNormal;

		// Water normal clamp
		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);
		worldNormal = normalize(worldNormal + tbnMatrix[2] * inversesqrt(maxEps(dot(tbnMatrix[2], -worldDir))));
		sceneOut = CalculateSpecularReflections(worldNormal, lightmap.y, viewPos.xyz);
	} else {
		albedo = texture(tex, texCoord) * tint;

		if (albedo.a < 0.1) { discard; return; }

		sceneOut = vec4(0.0);
		#if defined NORMAL_MAPPING
			worldNormal = texture(normals, texCoord).rgb;
			DecodeNormalTex(worldNormal);

			worldNormal = tbnMatrix * worldNormal;
			gbufferOut0.w = packUnorm2x8(encodeUnitVector(worldNormal));
		#else
			worldNormal = tbnMatrix[2];
		#endif
	}

	//==// Translucent lighting //================================================================//
	#ifdef TRANSLUCENT_LIGHTING
		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		float NdotL = dot(worldNormal, worldLightVector);

		// Sunlight
		vec3 sunlightMult = 30.0 * oneMinus(wetness * 0.96) * directIlluminance;

		vec3 sunlightDiffuse = vec3(0.0);
		vec3 specularHighlight = vec3(0.0);

		// float distanceFade = saturate(pow16(rcp(shadowDistance * shadowDistance) * dotSelf(worldPos)));

		// Shadows
		if (NdotL > 1e-3) {
			float distortFactor;
			vec3 normalOffset = tbnMatrix[2] * (dotSelf(worldPos) * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
			vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortFactor);	

			float LdotV = dot(worldLightVector, -worldDir);
			float dither = BlueNoiseTemporal(ivec2(gl_FragCoord.xy));

			vec2 blockerSearch = BlockerSearch(shadowScreenPos, dither);
			float penumbraScale = max(blockerSearch.x / distortFactor, 2.0 / realShadowMapRes);
			vec3 shadow = PercentageCloserFilter(shadowScreenPos, dither, penumbraScale) * saturate(lightmap.y * 1e8);

			if (maxOf(shadow) > 1e-6) {
				float NdotV = saturate(dot(worldNormal, -worldDir));
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = (NdotL + NdotV) * halfwayNorm;
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				shadow *= sunlightMult;

				sunlightDiffuse = shadow * fastSqrt(NdotL) * rPI;
				specularHighlight = shadow * 2.0 * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(0.005), materialID == 3u ? 0.02 : 0.04);
			}
		}

		if (materialID != 3u) {
			gbufferOut1.x = packUnorm2x8(albedo.rg);
			gbufferOut1.y = packUnorm2x8(albedo.ba);

			sceneOut.rgb += sunlightDiffuse;

			if (lightmap.y > 1e-5) {
				// Skylight
				vec3 skylight = skyIlluminance * 0.75;
				skylight = mix(skylight, directIlluminance * 0.05, wetness * 0.5 + 0.2);
				skylight *= worldNormal.y * 1.2 + 1.8;

				sceneOut.rgb += skylight * cube(lightmap.y);

				// Bounced light
				float bounce = CalculateFittedBouncedLight(worldNormal);
				bounce *= pow5(lightmap.y);
				sceneOut.rgb += bounce * sunlightMult;
			}

			if (lightmap.x > 1e-5) sceneOut.rgb += CalculateBlocklightFalloff(lightmap.x) * blackbody(float(BLOCKLIGHT_TEMPERATURE));

			sceneOut.a = fastSqrt(albedo.a) * TRANSLUCENT_LIGHTING_BLEND_FACTOR;
		}

		// Specular highlights
		sceneOut.rgb += specularHighlight;
		sceneOut.rgb /= maxEps(sceneOut.a);
	#else
		if (materialID != 3u) {
			gbufferOut1.x = packUnorm2x8(albedo.rg);
			gbufferOut1.y = packUnorm2x8(albedo.ba);
		}
	#endif
	//============================================================================================//

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut0.z = packUnorm2x8(encodeUnitVector(tbnMatrix[2]));
}