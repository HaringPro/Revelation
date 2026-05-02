
#include "/lib/surface/BRDF.glsl"

//================================================================================================//

float CalculateFakeBouncedLight(vec3 normal) {
	float bounce = saturate(dot(worldLightDir, vec3(0.01, 0.025, 0.01)));

	return approxSqrt(bounce * oms(0.75 * normal.y)) * uniformPhase;
}

float CalculateBlocklightFalloff(float blocklight) {
	blocklight = mix(blocklight, sqr(blocklight), 0.75);
	return blocklight * blocklight * blocklight;
}

vec3 HardCodeEmissive(uint materialID, vec3 albedo, vec3 worldPos) {
	float albedoLuminance = luminance(albedo);

	switch (materialID) {
		// Total emissive
		case 20u:
			return vec3(albedoLuminance);
		// Torch like
		case 21u:
			return approxSqrt(albedo) * 4.0 * step(min(0.6, albedo.b * 5.0), albedo.r);
		// Fire
		case 7u: case 22u:
			return approxSqrt(albedo) * 4.0;
		// Glowstone like
		case 23u:
			return vec3(4.0 * sdot(albedo));
		// Sea lantern like
		case 24u:
			return vec3(4.0 * albedoLuminance * albedoLuminance);
		// Redstone
		case 25u: {
			float mcPosFractY = fract(worldPos.y + cameraPosition.y);
			if (mcPosFractY > 0.18) return vec3(2.1, 0.9, 0.9) * step(0.4, albedo.r);
			else return vec3(2.1, 0.9, 0.9) * step(1.25, albedo.r / (albedo.g + albedo.b)) * step(0.2, albedo.r);
		}
		// Soul fire
		case 26u:
			return vec3(albedoLuminance * step(0.2, albedo.b) * 2.0);
		// Amethyst
		case 27u:
			return vec3((albedoLuminance + 0.4) * 0.5);
		// Glowberry
		case 28u:
			return vec3(saturate(dot(albedo, vec3(1.0, -0.6, -0.9)) - 0.1) * 16.0);
		// Rails
		case 29u:
			return vec3(2.1, 0.9, 0.9) * (albedoLuminance * step(albedo.g * 4.0, albedo.r));
		// Beacon core
		case 30u: {
			vec3 midBlockPos = abs(fract(worldPos + cameraPosition) - 0.5);
			if (maxOf(midBlockPos) < 0.4) return vec3(5.0 * albedoLuminance);
			else return vec3(0.0);
		}
		// Sculk
		case 31u:
			return vec3(0.05 * albedoLuminance * float((albedo.b * 2.0 > albedo.r + albedo.g) && albedo.b > 0.25));
		// Glow lichen
		case 32u:
			return vec3(albedoLuminance * 0.25 + step(albedo.b * 1.25, albedo.r) * 4.0);
		// Partial emissive
		case 33u:
			return 16.0 * sqr(saturate(albedo - 0.5));
		// Middle emissive
		case 34u: {
			vec2 midBlockPosXZ = abs(fract(worldPos.xz + cameraPosition.xz) - 0.5);
			return vec3(step(maxOf(midBlockPosXZ), 0.063) * albedoLuminance);
		}
		// End emissive
		case 46u:
			return vec3(64.0 * albedoLuminance);
		// Lightning bolt
		case 2000u:
			return vec3(16.0);
		// Default
		default:
			return vec3(0.0);
	}
}
