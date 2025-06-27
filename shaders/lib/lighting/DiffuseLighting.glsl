
#include "/lib/surface/BRDF.glsl"

//================================================================================================//

vec3 CalculateSubsurfaceScattering(in vec3 albedo, in float sssAmount, in float sssDepth, in float LdotV) {
	vec3 coeff = oms(0.75 * albedo) * (8.0 / sssAmount);

	float phase = HenyeyGreensteinPhase(-LdotV, 0.65) * 0.25 + uniformPhase * 0.75;
	vec3 subsurfaceScattering = exp2(coeff * sssDepth) * phase * sssAmount;

	return subsurfaceScattering * (PI * SUBSURFACE_SCATTERING_BRIGHTNESS);
}

float CalculateApproxBouncedLight(in vec3 normal) {
	float bounce = saturate(dot(worldLightVector, vec3(0.01, 0.03, 0.01)));

	return approxSqrt(bounce * oms(0.8 * normal.y)) * (0.5 * rPI);
}

//================================================================================================//

float CalculateBlocklightFalloff(in float blocklight) {
	float fade = rcp(sqr(16.0 - 15.0 * blocklight));
	blocklight += approxSqrt(blocklight) * 0.4 + sqr(blocklight) * 0.6;
	return blocklight * 0.5 * fade;
}

vec4 HardCodeEmissive(in uint materialID, in vec3 albedo, in vec3 albedoRaw, in vec3 worldPos, in vec3 blocklightColor) {
    float albedoLuminance = length(albedo);

    switch (materialID) {
        // Total glowing
        case 20u:
            return vec4(vec3(albedoLuminance), 0.1);
        // Torch like
        case 21u:
            return vec4(blocklightColor * (4.0 * float(albedoRaw.r > 0.8 || albedoRaw.r > albedoRaw.g * 1.4)), 0.15);
        // Fire
        case 7u: case 22u:
            return vec4(blocklightColor * (2.0 * cube(albedoLuminance)), 0.1);
        // Glowstone like
        case 23u:
            return vec4(blocklightColor * (2.5 * cube(albedoLuminance)), 0.15);
        // Sea lantern like
        case 24u:
            return vec4(vec3(4.0 * cube(albedoLuminance)), 0.0);
        // Redstone
        case 25u: {
            float worldPosYFract = fract(worldPos.y + cameraPosition.y);
            if (worldPosYFract > 0.18) return vec4(vec3(2.1, 0.9, 0.9) * step(0.65, albedoRaw.r), 1.0);
            else return vec4(vec3(2.1, 0.9, 0.9) * step(1.25, albedo.r / (albedo.g + albedo.b)) * step(0.5, albedoRaw.r), 1.0);
        }
        // Soul fire
        case 26u:
            return vec4(vec3((albedoLuminance + 0.6) * step(0.53, albedoRaw.b)), 0.5);
        // Amethyst
        case 27u:
            return vec4(vec3(albedoLuminance * 0.1), 1.0);
        // Glowberry
        case 28u:
            return vec4(saturate(dot(saturate(albedo - 0.1), vec3(1.0, -0.6, -0.99))) * vec3(28.0, 25.0, 21.0), 0.4);
        // Rails
        case 29u:
            return vec4(vec3(2.1, 0.9, 0.9) * (albedoLuminance * step(albedoRaw.g * 2.0 + albedoRaw.b, albedoRaw.r)), 1.0);
        // Beacon core
        case 30u: {
            vec3 midBlockPos = abs(fract(worldPos + cameraPosition) - 0.5);
            if (maxOf(midBlockPos) < 0.4 && albedo.b > 0.5) return vec4(vec3(6.0 * albedoLuminance), 0.0);
            else return vec4(vec3(0.0), 1.0);
        }
        // Sculk
        case 31u:
            return vec4(vec3(0.04 * sqr(albedoLuminance) * float((albedoRaw.b * 2.0 > albedoRaw.r + albedoRaw.g) && albedoRaw.b > 0.55)), 1.0);
        // Glow lichen
        case 32u:
            return vec4(albedoRaw.r > albedoRaw.b * 1.2 ? vec3(3.0) : vec3(albedoLuminance * 0.1), 1.0);
        // Partial glowing
        case 33u:
            return vec4(30.0 * albedoLuminance * cube(saturate(albedo - 0.5)), 0.5);
        // Middle glowing
        case 34u: {
            vec2 midBlockPosXZ = abs(fract(worldPos.xz + cameraPosition.xz) - 0.5);
            return vec4(vec3(step(maxOf(midBlockPosXZ), 0.063) * albedoLuminance), 1.0);
        }
        // End glowing
        case 46u:
            return vec4(vec3(1e2 * albedoLuminance), 0.0);
        // Lightning bolt
        case 60u:
            return vec4(vec3(4.0), 0.0);
        // Default
        default:
            return vec4(vec3(0.0), 1.0);
    }
}
