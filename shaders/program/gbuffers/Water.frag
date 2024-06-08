
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,3,4 */
layout(location = 0) out vec4 sceneOut;
layout(location = 1) out vec4 gbufferOut0;
layout(location = 2) out vec4 gbufferOut1;

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
in vec3 tangentViewDir;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

// #include "/lib/utility/Transform.inc"
// #include "/lib/utility/Fetch.inc"

#include "/lib/water/WaterWave.glsl"
// #include "/lib/water/WaterFog.glsl"

//======// Main //================================================================================//
void main() {

	vec3 normalOut;
	if (materialID == 3u) { // water
    	// ivec2 screenTexel = ivec2(gl_FragCoord.xy);
		// vec3 forwardPos = ScreenToViewSpace(vec3(texCoord, gl_FragCoord.z));
		// vec3 backPos = ScreenToViewSpace(vec3(texCoord, sampleDepthSoild(screenTexel)));

		// sceneOut = WaterFog(lightmap.y, distance(forwardPos, backPos));
		#ifdef WATER_PARALLAX
			normalOut = GetWavesNormal(minecraftPos.xz - minecraftPos.y, tangentViewDir);
		#else
			normalOut = GetWavesNormal(minecraftPos.xz - minecraftPos.y);
		#endif

		normalOut = normalize(tbnMatrix * normalOut);
		sceneOut = vec4(0.0);
	} else {
		vec4 albedo = texture(tex, texCoord) * tint;

		if (albedo.a < 0.1) { discard; return; }
		sceneOut = vec4(sqr(albedo.rgb), pow(albedo.a, 0.3));
		normalOut = tbnMatrix[2];
	}

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut1.x = packUnorm2x8(encodeUnitVector(normalOut));
	gbufferOut1.y = gbufferOut1.x;
}
