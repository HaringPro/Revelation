/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0
--------------------------------------------------------------------------------
*/

#define TEXTURE_CULL_DISTANCE 64.0 // [2 4 6 8 16 32 64 128 256 512 1024 2048]

#include "/lib/Utility.glsl"

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
layout (location = 3) out float parallaxShadowOut;
#endif

uniform sampler2D tex;
#if defined MC_NORMAL_MAP
    uniform sampler2D normals;
#endif
#if defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif
uniform vec4 entityColor;

#if defined MC_NORMAL_MAP
    in mat3 tbnMatrix;
    #define geoNormal tbnMatrix[2]
#else
    in vec3 geoNormal;
#endif

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;
in float viewDist;

float bayer2(vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

void main() {
    vec4 albedo = texture(tex, texCoord) * vertColor;

    // 半透明物品（染色玻璃、玻璃、冰等）以 alpha<1 渲染进 gbuffers_entities（Iris 下在
    // deferred 之后的半透明阶段），最终由 Translucent.comp 补合成。这里放宽丢弃阈值，
    // 避免纹理中较透明的像素被整片剔除导致整件物品不可见。
    if (albedo.a < 0.02) { discard; return; }
    #ifdef WHITE_WORLD
        albedo.rgb = vec3(1.0);
    #else
        if (materialID == 2000u) albedo.rgb = vec3(0.7, 0.675, 1.0);
    #endif

    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    // alpha 保持 1.0 输出，保证 colortex6 中 albedo 纯净（供 IntegrateScene 的玻璃
    // fallback 及 Grade 的雨滴遮蔽使用；colortex6 alpha 混合为 ZERO ONE 本就不写入）
    albedoOut = vec4(albedo.rgb, 1.0);

    uint matX = PackupDithered2x8U(lightmap, bayer4(gl_FragCoord.xy));
    uint matZ = 0u, matW = 0u;
    #if defined MC_SPECULAR_MAP
        if (viewDist < TEXTURE_CULL_DISTANCE) {
            vec4 specularTex = texture(specular, texCoord);
            matZ = Packup2x8U(specularTex.xy);
            matW = Packup2x8U(specularTex.zw);
        }
    #endif

    // 实体标志 (bit0) + 受伤标志 (bit1)
    float hurt = float(entityColor.a > 0.0 && entityColor.b < 0.1);
    uint flags = 1u | (uint(hurt) << 1);
    matW = (matW & 0xFCu) | flags;

    // 半透明实体（纹理 alpha<1，如彩色玻璃、冰等掉落物）复用方块玻璃管线：
    // materialID 置为 2u，并把真实 albedo(rgba) 打包进 materialPack.zw（与方块玻璃
    // Water.frag 完全一致），IntegrateScene 玻璃分支将用同样的公式（折射+染色+反射）
    // 处理，效果与方块玻璃一致。注意：此处不再保留 matW 低位的实体/受伤标志，
    // 半透明像素由方块玻璃分支渲染，不受 Final.frag 实体故障特效影响。
    // 不透明贴图实体保留原 materialID，由 Translucent.comp 补合成保证可见。
    uint outMaterialID = materialID;
    if (albedo.a < 1.0 - 0.001) {
        outMaterialID = 2u;
        matZ = Packup2x8U(albedo.xy);
        matW = Packup2x8U(albedo.zw);
    }
    materialOut = uvec4(matX, outMaterialID, matZ, matW);

    vec2 packedGeo = OctEncodeSnorm(geoNormal);
    #if defined MC_NORMAL_MAP
        if (viewDist < TEXTURE_CULL_DISTANCE) {
            vec3 normalTex = texture(normals, texCoord).rgb;
            DecodeNormalTex(normalTex);
            normalOut = vec4(packedGeo, OctEncodeSnorm(tbnMatrix * normalTex));
        } else {
            normalOut = vec4(packedGeo, packedGeo);
        }
    #else
        normalOut = vec4(packedGeo, packedGeo);
    #endif

    #if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
        parallaxShadowOut = 0.0;
    #endif
}