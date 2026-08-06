//#version 430 compatibility
/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Performance Optimized: reduced redundant computations, early exits,
                           combined conditionals, minor math simplifications.
    Fix: Clear low 2 bits of materialOut.w to avoid entity flag conflicts.
    Feature: Voxel Mapping Integration
--------------------------------------------------------------------------------
*/
// 视差映射最大距离（米），超出此距离视差完全失效
#define PARALLAX_MAX_DISTANCE 8.0  // [2 4 6 8 16 32 64 128 256 512 1024 2048]

// 视差映射淡化距离（米）
#define PARALLAX_FADE_START 64.0  // [2 4 6 8 16 32 64 128 256 512 1024 2048]
#define PARALLAX_FADE_END   32.0  // [2 4 6 8 16 32 64 128 256 512 1024 2048]

// 方块法线/高光贴图裁剪最大距离（米）
#define BLOCK_TEXTURE_CULL_DISTANCE 128.0  // [2 4 6 8 16 32 64 128 256 512 1024 2048]

// === Voxel Settings ===
// ENABLE_VOXELIZATION 和 VISUALIZE_VOXELS 由 shaders.properties 注入，此处不再重复定义
#define VOXEL_AREA 64     // [32 64 128]
#define VOXEL_RADIUS (VOXEL_AREA/2)

#include "/lib/Utility.glsl"

/* RENDERTARGETS: 6,7,8 */
layout (location = 0) out vec4 albedoOut;
layout (location = 1) out uvec4 materialOut;
layout (location = 2) out vec4 normalOut;

#if defined PARALLAX && defined PARALLAX_SHADOW && !defined PARALLAX_DEPTH_WRITE
layout (location = 3) out float parallaxShadowOut;
#endif

flat in uint normalPack;
#if defined MC_NORMAL_MAP
flat in uvec2 tangentPack;
#endif

in vec3 vertColor;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
    in vec2 tileBase;
    flat in vec2 tileScale;
    flat in vec2 tileOffset;
#endif

// --- Voxel Inputs ---
in vec3 block_centered_relative_pos;
uniform sampler3D voxelDataSampler;  // 可视化读取体素数据（atlas 引用格式，RGBA16，shadow pass 写入）
// 无显式 binding：gbuffers 的 image 与方块图集等普通贴图共用同一套硬件纹理单元，
// 显式 binding 会覆盖 Iris 的运行时分配，导致 imageAtomicMax 写到错误单元（全黑根因）。
// 照抄 ITRP：由 shaders.properties 的 image.<name> = <samplerName> 按名字自动绑定。
// 注意：非 writeonly 的 image 变量强制要求格式限定符（r32ui / rgba16）。

uniform sampler2D tex;
#if defined MC_NORMAL_MAP
    uniform sampler2D normals;
#endif
#if defined MC_SPECULAR_MAP
    uniform sampler2D specular;
#endif
#include "/lib/universal/Uniform.glsl"
#include "/lib/universal/Random.glsl"
#include "/lib/universal/Transform.glsl"

#ifdef PARALLAX
    #include "/lib/surface/Parallax.glsl"
#endif

void main() {
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
    float dither = BlueNoise(ivec2(gl_FragCoord.xy), frameCounter);

    vec2 packedGeo = unpackSnorm2x16(normalPack);
    vec2 packedNormal = packedGeo;          // 默认输出几何法线

    float distSq;
    bool skipNormalSpecular = true;

    #if defined MC_NORMAL_MAP || defined MC_SPECULAR_MAP || defined PARALLAX
        vec3 viewPos = ScreenToViewPos(vec3(screenCoord, gl_FragCoord.z));
        distSq = dot(viewPos, viewPos);
        skipNormalSpecular = distSq > (BLOCK_TEXTURE_CULL_DISTANCE * BLOCK_TEXTURE_CULL_DISTANCE);
    #endif

    vec4 albedo;

    #ifdef PARALLAX
        vec2 parallaxCoord = texCoord;
        mat2 texGrad; // 提前声明，远距离不会赋值但不会用到

        if (skipNormalSpecular) {
            // 远距离：跳过导数，普通采样
            albedo = texture(tex, texCoord);
            if (albedo.a < 0.1) { discard; return; }
        } else {
            // 近距离：计算导数与 TBN
            texGrad = mat2(dFdx(texCoord), dFdy(texCoord));

            #if defined MC_NORMAL_MAP
                vec3 tangent   = OctDecodeSnorm(unpackSnorm2x16(tangentPack.x));
                vec3 normal    = OctDecodeSnorm(packedGeo);
                vec3 bitangent = cross(tangent, normal) * uintBitsToFloat(tangentPack.y);
                mat3 tbnMatrix = mat3(tangent, bitangent, normal);
            #endif

            vec4 normalTex = textureGrad(normals, parallaxCoord, texGrad[0], texGrad[1]);

            #ifdef PARALLAX_DEPTH_WRITE
                gl_FragDepth = gl_FragCoord.z;
            #endif

            if (normalTex.w < (1.0 - rcp255)) {
                bool doParallax = true;
                #ifdef PARALLAX_MAX_DISTANCE
                    if (distSq > PARALLAX_MAX_DISTANCE * PARALLAX_MAX_DISTANCE) doParallax = false;
                #endif

                if (doParallax) {
                    float tangentLength = sqrt(distSq);
                    #if defined(PARALLAX_FADE_START) && defined(PARALLAX_FADE_END)
                        float parallaxFade = clamp((PARALLAX_FADE_START - tangentLength) / (PARALLAX_FADE_START - PARALLAX_FADE_END), 0.0, 1.0);
                    #else
                        float parallaxFade = smoothstep(64.0, 32.0, tangentLength);
                    #endif

                    vec3 tangentPos = mat3(gbufferModelViewInverse) * viewPos * tbnMatrix;
                    vec3 offsetCoord = CalculateParallax(tangentPos / tangentLength, dither, parallaxFade);
                    parallaxCoord = atlasCoord(offsetCoord.xy);

                    normalTex = textureGrad(normals, parallaxCoord, texGrad[0], texGrad[1]);
                    DecodeNormalTex(normalTex.xyz);

                    if (offsetCoord.z < (1.0 - rcp255) && parallaxFade > EPS) {
                        #ifdef PARALLAX_DEPTH_WRITE
                            gl_FragDepth = ViewToScreenDepth(ScreenToViewDepth(gl_FragDepth) - oms(offsetCoord.z) * PARALLAX_DEPTH);
                        #elif defined PARALLAX_SHADOW
                            if (dot(tbnMatrix[2], worldLightDir) > 1e-3) {
                                parallaxShadowOut = CalculateParallaxShadow(worldLightDir * tbnMatrix, offsetCoord, dither, parallaxFade);
                            }
                        #endif
                        #ifdef PARALLAX_BASED_NORMAL
                            #define sampleHeight(uv) textureGrad(normals, atlasCoord(uv), texGrad[0], texGrad[1]).w
                            vec2 bias = 1e-2 / (tileScale * vec2(atlasSize));
                            float heightR = sampleHeight(offsetCoord.xy + vec2(bias.x, 0.0));
                            float heightL = sampleHeight(offsetCoord.xy - vec2(bias.x, 0.0));
                            float heightU = sampleHeight(offsetCoord.xy + vec2(0.0, bias.y));
                            float heightD = sampleHeight(offsetCoord.xy - vec2(0.0, bias.y));
                            float deltaX = heightL - heightR;
                            float deltaY = heightD - heightU;
                            normalTex.xyz = normalize(vec3(deltaX, deltaY, step(abs(deltaX) + abs(deltaY), 1e-3)));
                        #endif
                    }
                } else {
                    DecodeNormalTex(normalTex.xyz);
                }
            } else {
                DecodeNormalTex(normalTex.xyz);
            }

            packedNormal = OctEncodeSnorm(tbnMatrix * normalTex.xyz);

            albedo = textureGrad(tex, parallaxCoord, texGrad[0], texGrad[1]);
            if (albedo.a < 0.1) { discard; return; }
        }

    #else   // ---- 非视差分支 ----
        albedo = texture(tex, texCoord);
        if (albedo.a < 0.1) { discard; return; }

        if (!skipNormalSpecular) {
            #if defined MC_NORMAL_MAP
                vec3 tangent   = OctDecodeSnorm(unpackSnorm2x16(tangentPack.x));
                vec3 normal    = OctDecodeSnorm(packedGeo);
                vec3 bitangent = cross(tangent, normal) * uintBitsToFloat(tangentPack.y);
                mat3 tbnMatrix = mat3(tangent, bitangent, normal);

                vec3 normalTex = texture(normals, texCoord).xyz;
                DecodeNormalTex(normalTex);
                packedNormal = OctEncodeSnorm(tbnMatrix * normalTex);
            #endif
        }
    #endif

    // --- Voxel Visualization Injection ---
    // 嵌套单独 #ifdef（Iris 选项扫描只识别单独的 `#ifdef X`，不能用 `#if defined A && defined B`
    // 复合条件——会跳过整行导致 VISUALIZE_VOXELS 与 ENABLE_VOXELIZATION 两个开关都消失）
    #ifdef VISUALIZE_VOXELS
        #ifdef ENABLE_VOXELIZATION
        {
            // 读取体素数据（atlas 引用格式，RGBA16）并按相机位移重投影。
            // 数据为本帧（gbuffers 边写边读，边缘可能闪烁；调试功能，默认关闭）
            ivec3 voxVisCoord = ivec3(block_centered_relative_pos);
            ivec3 voxVisPrev = voxVisCoord + (cameraPositionInt - previousCameraPositionInt);
            if (all(greaterThanEqual(voxVisPrev, ivec3(0))) && all(lessThan(voxVisPrev, ivec3(VOXEL_AREA)))) {
                vec4 voxVisData = texelFetch(voxelDataSampler, voxVisPrev, 0);
                if (voxVisData.z > 0.5) {
                    albedo.rgb = texture(tex, voxVisData.xy).rgb;  // 图集 UV 中心采样（与 gbuffers 同图集）
                }
            }
        }
        #endif
    #endif

    // ---- 输出 GBuffer ----
    albedoOut = vec4(albedo.rgb * vertColor, 1.0);
    #ifdef WHITE_WORLD
        albedoOut = vec4(1.0);
    #endif

    uint matZ = 0u, matW = 0u;
    #if defined MC_SPECULAR_MAP
        if (!skipNormalSpecular) {
            #ifdef PARALLAX
                vec4 specularTex = textureGrad(specular, parallaxCoord, texGrad[0], texGrad[1]);
            #else
                vec4 specularTex = texture(specular, texCoord);
            #endif
            matZ = Packup2x8U(specularTex.xy);
            matW = Packup2x8U(specularTex.zw);
        }
    #endif

    materialOut = uvec4(PackupDithered2x8U(lightmap, dither), materialID, matZ, matW);
    materialOut.w &= 0xFCu;

    normalOut = vec4(packedGeo, packedNormal);
}