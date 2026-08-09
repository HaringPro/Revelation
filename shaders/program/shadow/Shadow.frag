/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0
--------------------------------------------------------------------------------
*/

#define PASS_SHADOW

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

// [2026-08-09] vec3 → vec4：a 存纹理不透明度，供阳光反弹的 AlbedoToAbsorption
// 计算彩色阴影（ITRP SimpleShadow 同款：玻璃等半透明物体会给反弹光线染色）。
layout (location = 0) out vec4 shadowcolor0Out;
layout (location = 1) out vec4 shadowcolor1Out;

//======// Input //===============================================================================//

in vec2 texCoordOut;
in vec3 vectorDataOut;
flat in uint isWaterOut;

#ifdef ENABLE_VOXELIZATION
flat in vec3 v_voxelCoord;   // 体素格坐标（imageStore 目标）
flat in float v_voxelID;     // 正=固体 / 负=透明
flat in float v_emissive;    // 发光量（材料 ID 硬编码 [20,31]）
flat in float v_skylight;    // 天空光 lightmap（0-1）
flat in float v_blocklight;  // 方块光 lightmap（0-1）
flat in vec2 v_midCoord;     // 方块图集 UV 中心
flat in float v_isVoxel;     // 1=体素 tile 像素

// 无显式 binding：Iris 按 properties 的 image.<name> = <samplerName> 自动绑定（照抄 ITRP）。
// 显式 binding 会与 Iris 给普通贴图分配的硬件纹理单元冲突（全黑根因，血泪教训 #1）。
layout (rgba16f) uniform writeonly image3D voxelData;      // xy=atlas UV 中心 z=voxelID(原值) w=texRes(16)
layout (r32ui) uniform uimage3D voxelLightData;            // x=emissive y=sky z=block（atomicMax 需读写权限，不能 writeonly）
#endif

//======// Uniform //=============================================================================//

uniform sampler2D tex;
#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Random.glsl"
#include "/lib/water/WaterWave.glsl"

//#define SHADOW_CULL_UNDERGROUND

//======// Main //================================================================================//
void main() {
    #ifdef ENABLE_VOXELIZATION
        // ---- 体素 tile 像素：直写 3D image（格式与 gbuffers 时代 Terrain.frag 完全一致）----
        if (v_isVoxel > 0.5) {
            // 同方块所有片元 midCoord/voxelID 同值 → imageStore 直接覆盖（无需 atomicMax）
            // w = Pack2xU8(texRes, skylight)（照抄 ITRP Shadow FSH L588：高 8 位纹理分辨率
            //（低配固定 16）、低 8 位天空光 lightmap）。skylight 走 imageStore（写胜）而非
            // voxelLightData 的 atomicMax——max 合并会把洞内格被缝隙面抬高的 sky 当整格值，
            // 导致 SUNLIGHT_LEAK_FIX 泄漏衰减失效；写胜语义下 w 即该方块写入时的真实 sky。
            // 消费端 VoxelGI.frag 用 VoxelUnpack2xU8Y(voxelData.w) 解出（VoxelData.glsl）。
            // [FIX 2026-08-06 草方块白] blocks.png 里草方块顶面/草皮是白色/浅灰（绿色靠顶点色
            // gl_Color tint 染色），只存 atlas UV → 反弹采样得白色 → 草方块反弹白光。改为：
            // 固体（正 ID）r/g=染过色中心色 RG（half）、w 高 8 位=染过色 B（8bit，替代固定
            // texRes=16）、w 低 8 位=skylight；透明（负 ID）r/g 保留 atlas UV（透明吸收采样用）、
            // w 保持 texRes+skylight。反弹端按 ID 区分解包（VoxelUnpack2xU8X）。
            vec2 rgStore;
            float wPack;
            if (v_voxelID > 0.5) {
                vec3 tintedAlbedo = texture(tex, v_midCoord).rgb * vectorDataOut;
                rgStore = tintedAlbedo.rg;
                wPack = (floor(clamp(tintedAlbedo.b, 0.0, 1.0) * 255.0) * 256.0
                       + floor(clamp(v_skylight, 0.0, 1.0) * 255.0)) / 65535.0;
            } else {
                rgStore = v_midCoord;
                wPack = (floor(clamp(16.0 / 255.0, 0.0, 1.0) * 255.0) * 256.0
                       + floor(clamp(v_skylight, 0.0, 1.0) * 255.0)) / 65535.0;
            }
            imageStore(voxelData, ivec3(v_voxelCoord), vec4(rgStore, v_voxelID, wPack));
            // 亮度类光数据仍 atomicMax。旧字节序 packUnorm4x8(emissive,sky,block,0)：
            // R=emissive(byte0) G=sky(byte8) B=block(byte16) → block光(uint高位) 压掉发射光(uint低位)
            // → 火把旁边高block光方块 atomicMax 胜出 → 火把发射被清零 → "六面突然全黑"（#6根因）。
            // 修复：发射光放 B 通道（byte 16-23），block光放 G（byte 8-15），sky放 R（byte 0-7）。
            uint lightPacked = packUnorm4x8(vec4(v_skylight, v_blocklight, v_emissive, 0.0));
            imageAtomicMax(voxelLightData, ivec3(v_voxelCoord), lightPacked);
            return;
        }

        // ---- 真阴影只落在右上区，Shift 后溢出像素丢弃（照抄 ITRP FSH L551-552）----
        if (clamp(gl_FragCoord.xy, vec2(VOXEL_TILE_WIDTH, 0.0), vec2(VOXEL_SHADOW_RES, VOXEL_SHADOW_WIDTH)) != gl_FragCoord.xy)
            discard;
    #endif

    // [优化] 移除了 SHADOW_CULL_UNDERGROUND。
    // 因为在 Vertex Shader 中被判定为地下的顶点已被设为 vec4(-1.0)，
    // 光栅化器会自动拦截屏幕外的三角形，此处的片段着色器根本不会执行，无需重复计算。

    if (isWaterOut == 1u) {
        vec3 waveNormal = CalculateWaterNormal(vectorDataOut.xz);
        shadowcolor1Out.xy = OctEncodeUnorm(waveNormal.xzy);
        shadowcolor1Out.w = 1.0;
        return;
    }

    vec4 albedo = texture(tex, texCoordOut);
    if (albedo.a < 0.1) discard;

    const float alphaThresh = 1.0 - rcp255;

    if (albedo.a > alphaThresh) {
        shadowcolor0Out = vec4(albedo.rgb * vectorDataOut, 1.0);
    } else {
        // a 存原始纹理不透明度（吸收计算用）；rgb 保持原有混合（PCSS 彩色阴影视觉不变）
        float opacity = albedo.a;
        albedo.a = approxSqrt(approxSqrt(albedo.a));
        shadowcolor0Out = vec4(mix(vec3(albedo.a), albedo.rgb * vectorDataOut, albedo.a), opacity);
    }

    shadowcolor1Out.w = 0.0;
}
