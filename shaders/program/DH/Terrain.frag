
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

//======// Input //===============================================================================//

flat in vec3 flatNormal;
in vec3 worldPos;

in vec3 vertColor;
in vec2 lightmap;
flat in uint materialID;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"

//======// Main //================================================================================//
void main() {
    float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), sdot(worldPos));
	float dither = BlueNoise(ivec2(gl_FragCoord.xy), frameCounter);

    if (alpha < dither) {
        discard;
        return;
    }

	albedoOut = vec4(vertColor, 1.0);
	/* Terrain noises */ {
		const float res = 8.0;
		const float strength = 0.5;

		mat3 tbnMatrix = ConstructTBN(flatNormal);

		vec2 noisePos = ((worldPos + cameraPosition) * tbnMatrix).xy;
		float noise = texture(noisetex, noisePos * (res / 256.0)).x * 2.0;

		albedoOut.rgb = pow(albedoOut.rgb, vec3(mix(1.0, noise, strength)));
	}

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = materialID;
	materialOut.zw = uvec2(0);

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}