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

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec3 worldPos;

//======// Uniform //=============================================================================//

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

// Thanks to GeForceLegend
const vec3[] COLORS = vec3[](
	vec3(0.022087, 0.098399, 0.110818),
	vec3(0.011892, 0.095924, 0.089485),
	vec3(0.027636, 0.101689, 0.100326),
	vec3(0.046564, 0.109883, 0.114838),
	vec3(0.064901, 0.117696, 0.097189),
	vec3(0.063761, 0.086895, 0.123646),
	vec3(0.084817, 0.111994, 0.166380),
	vec3(0.097489, 0.154120, 0.091064),
	vec3(0.106152, 0.131144, 0.195191),
	vec3(0.097721, 0.110188, 0.187229),
	vec3(0.133516, 0.138278, 0.148582),
	vec3(0.070006, 0.243332, 0.235792),
	vec3(0.196766, 0.142899, 0.214696),
	vec3(0.047281, 0.315338, 0.321970),
	vec3(0.204675, 0.390010, 0.302066),
	vec3(0.080955, 0.314821, 0.661491)
);

vec2 endPortalLayer(vec2 coord, float layer) {
	vec2 offset = vec2(8.5 / layer, (1.0 + layer / 3.0) * (frameTimeCounter * 0.0015)) + 0.25;

	mat2 rotate = rotateMat(radians(layer * layer * 8642.0 + layer * 18.0));

	return (4.5 - layer * 0.25) * (rotate * coord) + offset;
}

#ifdef RAIN_PUDDLES
	#include "/lib/surface/RainPuddle.glsl"
#endif

//======// Main //================================================================================//
void main() {
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        if (any(greaterThanEqual(gl_FragCoord.xy, scaledViewSize))) {
            discard;
        }
    #endif

    vec2 deltaUv1 = dFdx(texCoord);
    vec2 deltaUv2 = dFdy(texCoord);

	vec3 deltaPos1 = dFdx(worldPos);
	vec3 deltaPos2 = dFdy(worldPos);

	vec3 geoNormal = normalize(cross(deltaPos1, deltaPos2));

	// Construct TBN matrix
	#ifdef MC_NORMAL_MAP

        vec3 tangentPerp = deltaPos2 * deltaUv1.x - deltaPos1 * deltaUv2.x;
        vec3 tangent = normalize(cross(tangentPerp, geoNormal));

        vec3 bitangentPerp = deltaPos2 * deltaUv1.y - deltaPos1 * deltaUv2.y;
        vec3 bitangent = normalize(cross(bitangentPerp, geoNormal));

		mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);
	#endif

    // Increase detail reserve
    deltaUv1 *= 0.5;
    deltaUv2 *= 0.5;

	vec4 albedo = textureGrad(tex, texCoord, deltaUv1, deltaUv2) * vertColor;

	if (albedo.a < 0.1) discard;

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	#if defined MC_NORMAL_MAP
		vec3 normalTex = textureGrad(normals, texCoord, deltaUv1, deltaUv2).rgb;
		DecodeNormalTex(normalTex);
		vec3 normal = tbnMatrix * normalTex;
	#else
		vec3 normal = geoNormal;
	#endif

	#if defined PARALLAX && defined PARALLAX_SHADOW
		parallaxOffsetOut = 0.0;
	#endif

	#if defined MC_SPECULAR_MAP
		vec4 specularTex = textureGrad(specular, texCoord, deltaUv1, deltaUv2);
	#else
		vec4 specularTex = vec4(0.0);
	#endif

    // Render end portal
	if (materialID == 46u) {
		vec3 worldDir = normalize(worldPos);
		vec3 worldDirAbs = abs(worldDir);
		vec3 sampleMask = step(maxOf(worldDirAbs), worldDirAbs);
		vec3 samplePart = signMul(sampleMask, worldDir);
		float intersection = 1.0 / dot(sampleMask, worldDirAbs);
		vec3 sampleNDCRaw = samplePart - worldDir * intersection;
		vec2 sampleNDC = sampleNDCRaw.xy * vec2(sampleMask.y + samplePart.z, 1.0 - sampleMask.y) + sampleNDCRaw.z * vec2(-samplePart.x, sampleMask.y);
		vec2 portalCoord = sampleNDC * 0.5 + 0.5;

		vec3 portalColor = vec3(0.0);
		for (uint i = 0u; i < 16u; ++i) {
			portalColor += textureGrad(tex, endPortalLayer(portalCoord, float(i + 1)), deltaUv1, deltaUv2).rgb * COLORS[i];
		}
		albedo.rgb = portalColor;
		specularTex = vec4(1.0, 0.0, vec2(254.0 / 255.0));
	}

	albedoOut = albedo;

	materialOut.x = Pack2x8U(lightmap, BlueNoise(ivec2(gl_FragCoord.xy), frameCounter + 1));
	materialOut.y = materialID;

	// Compute rain puddles
	#ifdef RAIN_PUDDLES
		if (wetnessCustom > EPS) {
			ApplyRainPuddleMaterial(albedoOut.rgb, specularTex.rgb, worldPos, normal, geoNormal, lightmap.y);
		}
	#endif

	normalOut.xy = OctEncodeSnorm(geoNormal);
	normalOut.zw = OctEncodeSnorm(normal);

	materialOut.z = Pack2x8U(specularTex.xy);
	materialOut.w = Pack2x8U(specularTex.zw);
}
