/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Geometry Shader（参考实现 Shadow.glsl GSH 移植，低配简化）：
    - 真阴影三角形：加 bias 防漏光 → ShiftShadowNdcPos 挤到右上区（仅 ENABLE_VOXELIZATION）
    - 体素三角形：三角形质心 → 世界对齐网格坐标 → VoxelTexel_From_VoxelCoord
      Y 型平铺到阴影贴图左条带。太阳方向固定 → 体素化内容不随相机转动，
      根治 gbuffers 时代"转头/移动重播种 → 方格闪烁"。
    ENABLE_VOXELIZATION 关闭时保持原样（全幅真阴影，不 Shift）。
--------------------------------------------------------------------------------
*/

//======// Utility //================================================================================//
// 必须先 include（settings.glsl 里定义 ENABLE_VOXELIZATION），
// 否则下方 #ifdef 声明块在预处理时被剥离 → C1503 undefined variable（与 Shadow.vert/frag 一致）

#include "/lib/Utility.glsl"

//======// Layout //================================================================================//

layout(triangles) in;
layout(triangle_strip, max_vertices = 6) out;

//======// Input //================================================================================//

in vec2 texCoord[];
in vec3 vectorData[];
flat in uint isWater[];

#ifdef ENABLE_VOXELIZATION
in vec3 g_voxelCoord[];      // 含 toCenter*0.001 偏移（供 GS 质心平均 → voxelCoord）
in vec3 g_voxelCoordBase[];  // 无偏移（供 posDiff 完整方块检测——不能有偏移，会腐蚀边长）
flat in float g_voxelID[];
flat in float g_notInVoxel[];
flat in vec2 g_mcLightLevel[];
in float g_posInvalid[]; // 每顶点（非 flat）：1=顶点偏离整数网格

uniform mat4 shadowProjection;
uniform int renderStage;
#endif

//======// Output //================================================================================//

out vec2 texCoordOut;
out vec3 vectorDataOut;
flat out uint isWaterOut;

#ifdef ENABLE_VOXELIZATION
flat out vec3 v_voxelCoord;   // 体素格坐标（FSH 直接 imageStore 到 3D image）
flat out float v_voxelID;     // 正=固体 / 负=透明（与 gbuffers 时代一致的编码）
flat out float v_emissive;    // 发光量（材料 ID 硬编码 [20,31]）
flat out float v_skylight;    // 天空光 lightmap（0-1）
flat out float v_blocklight;  // 方块光 lightmap（0-1）
flat out vec2 v_midCoord;     // 方块图集 UV 中心（xy=voxelData 通道）
flat out float v_isVoxel;     // 1=体素 tile 像素（FSH 走 image 路径）0=真阴影像素
#endif

//======// Main //==================================================================================//

void main() {
    #ifdef ENABLE_VOXELIZATION

        // ---- 真阴影分支：bias + Shift（照抄 参考实现 GSH L238-270）----
        // 用无偏移 g_voxelCoordBase 计算边长（偏移版 g_voxelCoord 的 toCenter*0.001
        // 会让面三角每条边缩短 ~0.001 → 总和偏离 3.4142 达 0.003+
        // → 完整方块检测全失败 → 所有默认方块被丢弃 → 体素网格只剩光源没有墙）
        vec3 posDiff = vec3(
            distance(g_voxelCoordBase[0], g_voxelCoordBase[1]),
            distance(g_voxelCoordBase[1], g_voxelCoordBase[2]),
            distance(g_voxelCoordBase[2], g_voxelCoordBase[0])
        );

        bool shadowVaild = all(lessThan(abs(gl_in[0].gl_Position.xy), vec2(1.0)));
        shadowVaild = shadowVaild || all(lessThan(abs(gl_in[1].gl_Position.xy), vec2(1.0)));
        shadowVaild = shadowVaild || all(lessThan(abs(gl_in[2].gl_Position.xy), vec2(1.0)));

        if (shadowVaild) {
            float bias = saturate(max(posDiff.x, max(posDiff.y, posDiff.z)) * 0.5 - 1.0) * shadowProjection[0][0] * 0.3;

            for (int i = 0; i < 3; i++) {
                gl_Position = gl_in[i].gl_Position;
                gl_Position.z += bias;
                ShiftShadowNdcPos(gl_Position.xy);

                texCoordOut = texCoord[i];
                vectorDataOut = vectorData[i];
                isWaterOut = isWater[i];
                v_isVoxel = 0.0;
                EmitVertex();
            }
            EndPrimitive();
        }

        // ---- 体素分支：质心网格坐标 → Y 型平铺左条带（照抄 参考实现 GSH L277-444，去纹素对齐）----
        vec3 voxelCoord = floor(g_voxelCoord[0] * 0.33333333 + g_voxelCoord[1] * 0.33333333 + g_voxelCoord[2] * 0.33333333);

        if (all(bvec3(
            clamp(voxelCoord, vec3(0.0), vec3(float(VOXEL_AREA) - 1.0)) == voxelCoord,
            g_notInVoxel[0] + g_notInVoxel[1] + g_notInVoxel[2] < 0.5,
            // [FIX 2026-08-06] 发光地衣（materialID=32）是 CUTOUT 渲染阶段，原分支
            // （SOLID/TRANSLUCENT）会把它排除在体素外 → 地衣没有体素数据 → 不照亮周围。
            // 只对 CUTOUT 阶段的光源块（voxelID==32）放行；草/花/门等普通 CUTOUT 方块
            // 仍不进体素（避免幻影块，参考实现 同语义）。
            renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT
            || (renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT && g_voxelID[0] == 32.0)
        ))) {
            // midCoord = 三角形纹理包围盒中心（参考实现 语义；消费端 GetAtlasCoord 做精确纹素定位）
            vec2 maxTexCoord = max(texCoord[0], max(texCoord[1], texCoord[2]));
            vec2 minTexCoord = min(texCoord[0], min(texCoord[1], texCoord[2]));
            vec2 midCoord = (maxTexCoord + minTexCoord) * 0.5;

            float voxelID = g_voxelID[0];
            // 参考实现 PT_FULLBLOCK_DETECTION（GSH L416-426）：普通方块（voxelID==1，未列入
            // block.properties）的三角形须覆盖整格面（边长和 ≈ 3.41421356 = 2+√2，整块面
            // 三角 = 两单位边 + 面对角线）且三顶点全在整数网格（g_posInvalid 和=0）且非透明
            // 渲染阶段 → 才写入体素；半砖/楼梯/按钮等非整格面 → 跳过（"隐形幻影整块"根因）。
            // 发光(20-31)/形状(155-294)/透明负 ID 不受影响（各自独立路径）。
            if (voxelID == 1.0) {
                bool isFullBlock = abs(posDiff.x + posDiff.y + posDiff.z - 3.41421356)
                                   + g_posInvalid[0] + g_posInvalid[1] + g_posInvalid[2] < 0.001
                                   && renderStage != MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
                if (!isFullBlock) return;
            }
            // 发光检测：材料 ID 硬编码 [20,31]（block.properties block.10020-10031，不经 LabPBR 发射贴图）
            // [FIX 2026-08-06] 补充岩浆（7，TRANSLUCENT）与发光地衣（32，CUTOUT）为发射体素：
            // 原版方块光 lightmap 关闭时，岩浆/地衣不再靠 blocklight 反弹（依赖 albedo 中心色）发光，
            // 而是作为发射源像火把一样照亮周围。消费端 VoxelLightColor 已扩展对应颜色。
            float emissive = ((voxelID >= 20.0 && voxelID <= 31.0) || voxelID == 7.0 || voxelID == 32.0) ? 0.995 : 0.0;
            float skylight = g_mcLightLevel[0].y * 0.33333333 + g_mcLightLevel[1].y * 0.33333333 + g_mcLightLevel[2].y * 0.33333333;
            float blocklight = g_mcLightLevel[0].x * 0.33333333 + g_mcLightLevel[1].x * 0.33333333 + g_mcLightLevel[2].x * 0.33333333;

            vec2 voxelTexel = VoxelTexel_From_VoxelCoord(voxelCoord);
            const vec2[3] vertexOffset = vec2[3](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.5, 1.0));

            for (int i = 0; i < 3; i++) {
                gl_Position = vec4((voxelTexel + vertexOffset[i]) * (2.0 / VOXEL_SHADOW_RES) - 1.0, -0.75, 1.0);

                texCoordOut = texCoord[i];
                vectorDataOut = vectorData[i];
                isWaterOut = isWater[i];
                v_voxelCoord = voxelCoord;
                v_voxelID = voxelID;
                v_emissive = emissive;
                v_skylight = skylight;
                v_blocklight = blocklight;
                v_midCoord = midCoord;
                v_isVoxel = 1.0;
                EmitVertex();
            }
            EndPrimitive();
        }

    #else

        // 体素化关闭：原样转发（全幅真阴影，无 Shift）
        for (int i = 0; i < 3; i++) {
            gl_Position = gl_in[i].gl_Position;
            texCoordOut = texCoord[i];
            vectorDataOut = vectorData[i];
            isWaterOut = isWater[i];
            EmitVertex();
        }
        EndPrimitive();

    #endif
}
