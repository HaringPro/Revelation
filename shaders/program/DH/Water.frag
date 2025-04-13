
#define PASS_DH_WATER

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 1,7,8 */
layout (location = 0) out vec4 lightingOut;
layout (location = 1) out uvec3 gbufferOut0;
layout (location = 2) out vec2 gbufferOut1;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Input //===============================================================================//

flat in vec3 flatNormal;

in vec4 vertColor;
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

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 worldDir) {
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

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
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
    if (loadDepth0(ivec2(gl_FragCoord.xy)) < 1.0) { discard; return; }

	vec3 worldNormal;
	vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

	if (materialID == 3u) { // water
		#ifdef PHYSICS_OCEAN
			WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

			worldNormal = wave.normal;
			gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
		#else
			mat3 tbnMatrix = ConstructTBN(flatNormal);

			vec3 minecraftPos = worldPos + cameraPosition;
			#ifdef WATER_PARALLAX
				worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y, worldDir * tbnMatrix);
			#else
				worldNormal = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
			#endif

			gbufferOut1 = worldNormal.xy * 0.5 + 0.5;
			worldNormal = tbnMatrix * worldNormal;
		#endif

		// Water normal clamp
		worldNormal = normalize(worldNormal + flatNormal * inversesqrt(maxEps(dot(flatNormal, -worldDir))));
	} else {
		vec4 albedo = vertColor;

		worldNormal = flatNormal;
		gbufferOut0.z = Packup2x8U(encodeUnitVector(worldNormal));

		gbufferOut1.x = Packup2x8(albedo.rg);
		gbufferOut1.y = Packup2x8(albedo.ba);
	}

	//==// Translucent lighting //================================================================//

	// Indirect specular lighting
	lightingOut = CalculateSpecularReflections(worldNormal, lightmap.y, worldDir);

	// Cloud shadows
	#ifdef CLOUD_SHADOWS
		// float cloudShadow = CalculateCloudShadows(worldPos);
		vec2 cloudShadowCoord = WorldToCloudShadowCoord(worldPos);
		float cloudShadow = textureBicubic(colortex10, saturate(cloudShadowCoord)).x;
		cloudShadow = min(cloudShadow, 1.0 - wetness * 0.6);
	#else
		float cloudShadow = 1.0 - wetness * 0.96;
	#endif

	// Sunlight
	vec3 sunlightMult = cloudShadow * directIlluminance;
	float NdotL = dot(worldNormal, worldLightVector);

	// Direct specular lighting
	if (NdotL > 1e-3) {
		float distortFactor;
		float worldDistSquared = sdot(worldPos);

		vec3 normalOffset = flatNormal * (worldDistSquared * 1e-4 + 3e-2) * (2.0 - saturate(NdotL));
		vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortFactor);	

		if (saturate(shadowScreenPos) == shadowScreenPos) {
			float dither = BlueNoiseTemporal(ivec2(gl_FragCoord.xy));

			float blockerSearch = BlockerSearch(shadowScreenPos, dither, 0.25 / distortFactor);
			shadowScreenPos.z -= (worldDistSquared * 1e-9 + 3e-6) * (1.0 + dither) * distortFactor * shadowDistance;

			vec3 shadow = PercentageCloserFilter(shadowScreenPos, worldPos, dither, blockerSearch.x / distortFactor) * saturate(lightmap.y * 1e8);

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