
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 2,3,4 */
layout (location = 0) out vec4 sceneOut;
layout (location = 1) out vec4 gbufferOut0;
layout (location = 2) out vec4 gbufferOut1;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

#include "/lib/utility/Uniform.inc"

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 minecraftPos;
in vec4 viewPos;

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"
#include "/lib/utility/Noise.inc"

#include "/lib/atmospherics/Global.inc"

#include "/lib/water/WaterWave.glsl"
// #include "/lib/water/WaterFog.glsl"

#include "/lib/surface/BRDF.glsl"

#include "/lib/surface/ScreenSpaceRaytracer.glsl"

vec4 CalculateSpecularReflections(in vec3 normal, in float skylight, in vec3 viewPos) {
	skylight = smoothstep(0.3, 0.8, skylight);
	vec3 viewDir = normalize(viewPos);
	normal = mat3(gbufferModelView) * normal;

	float LdotH = dot(normal, -viewDir);
	vec3 rayDir = viewDir + normal * LdotH * 2.0;

	float NdotL = dot(normal, rayDir);
	if (NdotL < 1e-6) return vec4(0.0);

	float dither = InterleavedGradientNoiseTemporal(gl_FragCoord.xy);
	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, gl_FragCoord.z);

	vec3 reflection;
	if (skylight > 1e-3) {
		if (isEyeInWater == 0) {
			vec3 rayDirWorld = mat3(gbufferModelViewInverse) * rayDir;
			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(rayDirWorld)).rgb;

			reflection = skyRadiance * skylight;
		} else if (materialID == 3u) {
			reflection = skyIlluminance * rPI;
		}
	}

	float NdotV = max(1e-6, dot(normal, -viewDir));
	bool hit = ScreenSpaceRaytrace(viewPos, rayDir, dither, RAYTRACE_SAMPLES, screenPos);
	if (hit) {
		screenPos.xy *= viewPixelSize;
		vec2 previousCoord = Reproject(screenPos).xy;
		if (saturate(previousCoord) == previousCoord) {
			float edgeFade = screenPos.x * screenPos.y * oneMinus(screenPos.x) * oneMinus(screenPos.y);
			reflection += (texelFetch(colortex7, rawCoord(previousCoord), 0).rgb - reflection) * saturate(edgeFade * 5e2);
		}
	}

	float brdf;
	if (isEyeInWater == 1) { // 全反射
		//specular = FresnelDielectricN(NdotV, 1.000293 / WATER_REFRACT_IOR);
		brdf = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
	} else {
		brdf = FresnelDielectricN(NdotV, materialID == 3u ? WATER_REFRACT_IOR : GLASS_REFRACT_IOR);
	}

	return clamp16f(vec4(reflection, brdf));
}

//======// Main //================================================================================//
void main() {

	vec3 normalOut;
	if (materialID == 3u) { // water
    	// ivec2 screenTexel = ivec2(gl_FragCoord.xy);
		// vec3 forwardPos = ScreenToViewSpace(vec3(texCoord, gl_FragCoord.z));
		// vec3 backPos = ScreenToViewSpace(vec3(texCoord, sampleDepthSoild(screenTexel)));

		// sceneOut = WaterFog(lightmap.y, distance(forwardPos, backPos));
		#ifdef WATER_PARALLAX
			normalOut = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y, normalize(minecraftPos - cameraPosition) * tbnMatrix);
		#else
			normalOut = CalculateWaterNormal(minecraftPos.xz - minecraftPos.y);
		#endif

		normalOut = normalize(tbnMatrix * normalOut);
		sceneOut = CalculateSpecularReflections(normalOut, lightmap.y, viewPos.xyz);
	} else {
		vec4 albedo = texture(tex, texCoord) * tint;

		if (albedo.a < 0.1) { discard; return; }
		sceneOut = vec4(sqr(albedo.rgb) * (skyIlluminance + directIlluminance), pow(albedo.a, 0.3));
		normalOut = tbnMatrix[2];

		vec4 reflections = CalculateSpecularReflections(normalOut, lightmap.y, viewPos.xyz);
		sceneOut.rgb += (reflections.rgb - sceneOut.rgb) * reflections.a;
		sceneOut.rgb /= maxEps(sceneOut.a);
	}

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut1.x = packUnorm2x8(encodeUnitVector(normalOut));
	gbufferOut1.y = gbufferOut1.x;
}
