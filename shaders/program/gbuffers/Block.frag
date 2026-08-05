/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0
--------------------------------------------------------------------------------
*/

#include "/lib/Utility.glsl"

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
layout (location = 3) out float parallaxShadowOut;
#endif

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;
in vec3 worldPos;

uniform sampler2D tex;
#if defined MC_NORMAL_MAP
    uniform sampler2D normals;
#endif
#if defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;

float bayer2(vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

// ✨ 低配优化：传送门层数（可改为 8、4、2）
#ifndef PORTAL_LAYERS
    #define PORTAL_LAYERS 4 // [2 4 6 8 10 12 14 16]
#endif

// ✨ 颜色数组跟随层数自动截断
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

// ✨ 层角度数组同样截断，用函数返回以避免全局大数组
float getPortalAngle(int layerIndex) {
    // 公式：(layer+1)^2 * 8642 + (layer+1)*18 转为弧度
    float layer = float(layerIndex + 1);
    return radians(layer * layer * 8642.0 + layer * 18.0);
}

vec2 endPortalLayerFast(vec2 coord, int layerIndex) {
    float layer = float(layerIndex + 1);
    vec2 offset = vec2(8.5 / layer, (1.0 + layer / 3.0) * (frameTimeCounter * 0.0015)) + 0.25;
    float angle = getPortalAngle(layerIndex);
    float cosA = cos(angle);
    float sinA = sin(angle);
    vec2 rotCoord = vec2(cosA * coord.x - sinA * coord.y, sinA * coord.x + cosA * coord.y);
    return (4.5 - layer * 0.25) * rotCoord + offset;
}

//======// Main //================================================================================//
void main() {
    vec4 albedo = texture(tex, texCoord) * vertColor;

    vec3 deltaPos1 = dFdxCoarse(worldPos);
    vec3 deltaPos2 = dFdyCoarse(worldPos);
    vec3 geoNormal = normalize(cross(deltaPos1, deltaPos2));

    #ifdef MC_NORMAL_MAP
        vec3 deltaPos1Perp = cross(geoNormal, deltaPos1);
        vec3 deltaPos2Perp = cross(deltaPos2, geoNormal);

        vec2 deltaUv1 = dFdxCoarse(texCoord);
        vec2 deltaUv2 = dFdyCoarse(texCoord);

        // 优化：避免双重归一化
        vec3 t_un = deltaPos2Perp * deltaUv1.x + deltaPos1Perp * deltaUv2.x;
        vec3 b_un = deltaPos2Perp * deltaUv1.y + deltaPos1Perp * deltaUv2.y;
        float maxSq = max(dot(t_un, t_un), dot(b_un, b_un));
        float invmax = inversesqrt(maxSq);
        vec3 tangent = t_un * invmax;
        vec3 bitangent = b_un * invmax;

        mat3 tbnMatrix = mat3(tangent, bitangent, geoNormal);
    #endif

    if (albedo.a < 0.1) { discard; return; }

    #ifdef WHITE_WORLD
        albedo.rgb = vec3(1.0);
    #endif

    if (materialID == 46u) {
    vec3 worldDir = normalize(worldPos);
    vec3 worldDirAbs = abs(worldDir);
    vec3 samplePartAbs = step(maxOf(worldDirAbs), worldDirAbs);
    vec3 samplePart = signMul(samplePartAbs, worldDir);
    float intersection = 1.0 / dot(samplePartAbs, worldDirAbs);
    vec3 sampleNDCRaw = samplePart - worldDir * intersection;
    vec2 sampleNDC = sampleNDCRaw.xy * vec2(samplePartAbs.y + samplePart.z, 1.0 - samplePartAbs.y) + sampleNDCRaw.z * vec2(-samplePart.x, samplePartAbs.y);
    vec2 portalCoord = sampleNDC * 0.5 + 0.5;

    // ✨ 始终从最明亮的层开始，只叠加 PORTAL_LAYERS 层
    vec3 portalColor = vec3(0.0);
    for (int i = 15; i > 15 - PORTAL_LAYERS; --i) {
        vec2 layerCoord = endPortalLayerFast(portalCoord, i);
        portalColor += texture(tex, layerCoord).rgb * COLORS[i];
    }
    albedo.rgb = portalColor;
}

    albedoOut = albedo;

    materialOut.x = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
    materialOut.y = materialID;

    #if defined MC_SPECULAR_MAP
        vec4 specularTex = texture(specular, texCoord);
        materialOut.z = Packup2x8U(specularTex.xy);
        materialOut.w = Packup2x8U(specularTex.zw);
    #else
        materialOut.zw = uvec2(0);
    #endif

    materialOut.w &= 0xFCu;   // 清除低2位，防止实体标志泄露

    normalOut.xy = OctEncodeSnorm(geoNormal);
    #if defined MC_NORMAL_MAP
        vec3 normalTex = texture(normals, texCoord).rgb;
        DecodeNormalTex(normalTex);
        normalOut.zw = OctEncodeSnorm(tbnMatrix * normalTex);
    #else
        normalOut.zw = normalOut.xy;
    #endif

    #if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
        parallaxShadowOut = 0.0;
    #endif
}