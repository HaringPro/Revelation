
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 1,7,8 */
layout (location = 0) out vec4 lightingOut;
layout (location = 1) out uvec3 gbufferOut0;
layout (location = 2) out vec2 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#if defined NORMAL_MAPPING
	uniform sampler2D normals;
#endif

#if defined SPECULAR_MAPPING && defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif

#include "/lib/universal/Uniform.glsl"

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 worldPos;
in vec3 viewPos;

flat in vec3 directIlluminance;

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"
#include "/lib/universal/Offset.glsl"

#include "/lib/atmosphere/Global.glsl"

#define PHYSICS_OCEAN_SUPPORT

#ifdef PHYSICS_OCEAN
	#define PHYSICS_FRAGMENT
	#include "/lib/water/PhysicsOceans.glsl"
#else
	#include "/lib/water/WaterWave.glsl"
#endif
#ifdef CLOUD_SHADOWS
	#include "/lib/atmosphere/clouds/Shadows.glsl"
#endif

#include "/lib/lighting/Shadows.glsl"
#include "/lib/lighting/DiffuseLighting.glsl"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in vec3 worldDir, in float dither, in float skylight) {
	skylight = remap(0.3, 0.7, cube(skylight));

	float NdotV = abs(dot(normal, worldDir));
    // Unroll the reflect function manually
	vec3 rayDir = worldDir + normal * NdotV * 2.0;

	if (dot(normal, rayDir) < 1e-6) return vec4(0.0);

	float f0 = F0FromIOR(materialID == 3u ? WATER_REFRACT_IOR : GLASS_REFRACT_IOR);
	bool withinWater = isEyeInWater == 1 && materialID == 3u;

	vec3 reflection = vec3(0.0);
	if (skylight > 1e-3 && !withinWater) {
		vec2 skyViewCoord = FromSkyViewLutParams(rayDir) + vec2(0.0, 0.5);
		vec3 skyRadiance = textureBicubic(colortex5, skyViewCoord).rgb;

		reflection = skyRadiance * skylight;
	}

	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z);

	float brdf;

    // Fresnel term
	if (withinWater) {
		// Total internal reflection
		brdf = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
	} else {
		brdf = FresnelDielectric(NdotV, f0);
	}
	uint raySteps = uint(mix(6u, RAYTRACE_SAMPLES, brdf));

	bool hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * rayDir, dither, raySteps, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		float edgeFade = screenPos.x * screenPos.y * oms(screenPos.x) * oms(screenPos.y);
		edgeFade *= 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * 4e3;
		reflection += (texelFetch(colortex4, uvToTexel(screenPos.xy * 0.5), 0).rgb - reflection) * saturate(edgeFade);
	}

	return satU16f(vec4(reflection * brdf, brdf));
}

//======// Main //================================================================================//
void main() {
	vec3 worldNormal;
	vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);
	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);

	if (materialID == 3u) { // water
		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			worldNormal = wave.normal;
			#ifndef RAYTRACED_REFRACTION
				gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
			#endif
		#else
			vec3 minecraftPos = worldPos + cameraPosition;
			vec2 tangentPos = ((minecraftPos * vec3(1.0, 0.15, 1.0)) * tbnMatrix).xy;
			#ifdef WATER_PARALLAX
				worldNormal = CalculateWaterNormal(tangentPos, worldDir * tbnMatrix, dither);
			#else
				worldNormal = CalculateWaterNormal(tangentPos);
			#endif

			#ifndef RAYTRACED_REFRACTION
				gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
			#endif
			worldNormal = tbnMatrix * worldNormal;
		#endif

		#ifdef RAYTRACED_REFRACTION
			gbufferOut0.z = Packup2x8U(OctEncodeUnorm(worldNormal));
		#endif

		// Water normal clamp
		worldNormal = normalize(worldNormal + tbnMatrix[2] * inversesqrt(maxEps(dot(tbnMatrix[2], -worldDir))));
	} else {
		vec4 albedo = texture(tex, texCoord) * vertColor;

		if (albedo.a < 0.1) { discard; return; }

		#if defined NORMAL_MAPPING
			worldNormal = texture(normals, texCoord).rgb;
			DecodeNormalTex(worldNormal);

			worldNormal = tbnMatrix * worldNormal;
		#else
			worldNormal = tbnMatrix[2];
		#endif
		gbufferOut0.z = Packup2x8U(OctEncodeUnorm(worldNormal));

		gbufferOut1.x = Packup2x8(albedo.rg);
		gbufferOut1.y = Packup2x8(albedo.ba);
	}

	//==// Translucent lighting //================================================================//

	// Indirect specular lighting
	lightingOut = CalculateSpecularReflections(worldNormal, worldDir, dither, lightmap.y);

	// Cloud shadows
	#ifdef CLOUD_SHADOWS
		// float cloudShadow = CalculateCloudShadows(worldPos);
		vec2 cloudShadowCoord = WorldToCloudShadowPos(worldPos);
		float cloudShadow = textureBicubic(colortex10, saturate(cloudShadowCoord)).x;
	#else
		float cloudShadow = 1.0 - wetness * 0.96;
	#endif

	// Sunlight
	vec3 sunlightMult = cloudShadow * directIlluminance;
	float NdotL = dot(worldNormal, worldLightVector);

	// Direct specular lighting
	if (NdotL > 1e-3) {
		float distortionFactor;
		float worldDistSquared = sdot(worldPos);

		vec3 normalOffset = tbnMatrix[2] * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
		vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortionFactor);	

		if (saturate(shadowScreenPos) == shadowScreenPos) {
			float blockerSearch = BlockerSearch(shadowScreenPos, dither, 0.25 * distortionFactor);
			shadowScreenPos.z -= (worldDistSquared * 1e-9 + 3e-6) * (1.0 + dither) / distortionFactor * shadowDistance;

			vec3 shadow = PercentageCloserFilter(shadowScreenPos, worldPos, dither, blockerSearch.x * distortionFactor) * saturate(lightmap.y * 1e8);

			if (dot(shadow, vec3(1.0)) > 1e-6) {
				float LdotV = dot(worldLightVector, -worldDir);
				float NdotV = abs(dot(worldNormal, -worldDir));
				float halfwayNorm = inversesqrt(2.0 * LdotV + 2.0);
				float NdotH = saturate((NdotL + NdotV) * halfwayNorm);
				float LdotH = LdotV * halfwayNorm + halfwayNorm;

				shadow *= sunlightMult;

				float f0 = F0FromIOR(materialID == 3u ? WATER_REFRACT_IOR : GLASS_REFRACT_IOR);
				lightingOut.rgb += shadow * SpecularBRDF(LdotH, NdotV, NdotL, NdotH, sqr(TRANSLUCENT_ROUGHNESS), f0);
			}
		}
	}

	//============================================================================================//

	gbufferOut0.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = materialID;
}