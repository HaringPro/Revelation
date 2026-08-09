/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0
--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //================================================//

out vec2 texCoord;
out vec3 vectorData; // Minecraft position in water, vertColor in other materials
flat out uint isWater;

// 传递给 GS 的体素化数据（编码语义照抄 gbuffers Terrain.vert，坐标系必须与查询端一致）
#ifdef ENABLE_VOXELIZATION
out vec3 g_voxelCoord;       // 含 toCenter*0.001 偏移（imageStore 目标 → GS 质心平均后 floor）
out vec3 g_voxelCoordBase;   // 无偏移（供 GS posDiff 完整方块检测——偏移会腐蚀边长度使检测全失败）
flat out float g_voxelID;    // 正=固体 / 负=透明（水3 叶13 植物1000-1003 传送门1500）
flat out float g_notInVoxel; // 1=实体/无方块（mc_Entity.x<=0.5），0=地形方块
flat out vec2 g_mcLightLevel;// x=方块光 y=天空光（原版 lightmap 0-1）
out float g_posInvalid;      // 1=顶点偏离整数网格（非完整方块信号，仅 materialID==1 有效）
#endif

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec4 at_midBlock;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform vec3 cameraPosition;
uniform mat4 shadowModelViewInverse;
uniform int blockEntityId;
#ifdef ENABLE_VOXELIZATION
uniform vec3 cameraPositionFract; // Iris Exclusive
#endif

//======// Function //============================================================================//

#include "/lib/lighting/shadow/Common.glsl"
//======//

//======// Main //================================================================================//
void main() {
    // [优化] 1. 将所有剔除判断放到最上方
    #ifdef SHADOW_CULL_UNDERGROUND
        if (eyeSkylightSmooth < 0.01) {
            gl_Position = vec4(-1.0);
            return;
        }
    #endif

    if (blockEntityId == 10030) {
        gl_Position = vec4(-1.0);
        return;
    }

    #ifdef SHADOW_BACKFACE_CULLING
        if ((gl_NormalMatrix * gl_Normal).z < 0.0) {
            gl_Position = vec4(-1.0);
            return;
        }
    #endif

    // [优化] 3. 确认顶点存活后进行空间变换
    vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
    gl_Position.xyz = DistortShadowSpace(projMAD(gl_ProjectionMatrix, viewPos));
    gl_Position.w = 1.0;

    texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

    // 玩家相对世界坐标（shadowModelViewInverse 不含相机平移，与 gbuffers 的 worldPos 同一约定）
    vec3 scenePos = transMAD(shadowModelViewInverse, viewPos);

    // [优化] 4. 避免强制类型转换开销
    if (abs(mc_Entity.x - 10003.0) < 0.1) {
        isWater = 1u;
        vectorData = scenePos + cameraPosition;
    } else {
        isWater = 0u;
        vectorData = gl_Color.rgb;
    }

    // 体素化输出（照抄 gbuffers Terrain.vert L80-109：世界对齐网格，GS 按质心平铺进阴影左条带）
    #ifdef ENABLE_VOXELIZATION
        uint materialID = uint(max(mc_Entity.x - 1e4, 1));
        bool translucent = (materialID == 3u || materialID == 4u || materialID == 13u ||
                            (materialID >= 1000u && materialID <= 1003u) || materialID == 1500u);
        g_voxelID = translucent ? -float(materialID) : float(materialID);
        // [FIX 2026-08-05] g_notInVoxel 不能用 mc_Entity.x 判定"实体"：
        // 未列入 block.properties 的普通方块（stone/dirt/grass/planks…）mc_Entity.x 同样是 0
        //（与实体无法区分）→ 会被 step(0,0.5)=1 误判为实体 → GS 门限 g_notInVoxel 和<0.5
        // 恒不满足 → 普通方块全被排除出体素化 → "网格只有光源/玻璃没有墙" → 追踪永远不命中
        // 实体 → 方块光/阳光反弹全无（只剩发射光辉光）。改由 GS 的 renderStage 门限
        //（SOLID/TRANSLUCENT）作为唯一过滤：实体在 ENTITIES/BLOCK_ENTITIES 等阶段被排除。
        g_notInVoxel = 0.0;
        // 参考实现 PT_FULLBLOCK_DETECTION（Shadow.glsl VSH L155-169）：未列入 block.properties 的
        // 方块（mc_Entity.x=0 → materialID=1，同时涵盖完整方块与按钮/告示牌/漏网半砖等
        // 非完整方块）材质 ID 无法区分，改由几何判定：顶点不在整数网格 → 标记，
        // GS 端按三角形边长和判定是否覆盖整格面，非整格面不写入体素（消除"幻影整块"）。
        // 发光(20-31)/形状(155-294)/透明等已列出的材料不受影响（参考实现 只查 g_voxelID<=1）。
        g_posInvalid = 0.0;
        if (materialID == 1u) {
            // [FIX 2026-08-06 最终根因] gl_Vertex 在 shadow pass 是相机相对/世界坐标
            //（带相机小数位偏移），abs(gl_Vertex - round(gl_Vertex)) 恒 ≈ 相机小数 Cf ≠ 0
            // → g_posInvalid 恒 1 → GS 整块检测把 materialID==1 的普通方块（石头/泥土/草/
            // 木板…）全过滤 → 体素网格只有发光块（火把粉红）和形状块（155-294 不查此分支），
            // 普通地形全空（DEBUG 全蓝）→ 追踪命中不到真实地形 → 阳光反弹全无。
            // 改用世界对齐整数坐标：scenePos = camrel（W−C），+cameraPositionFract = W−floor(C)
            //（精确整数，与 g_voxelCoordBase/查询端同口径）。完整方块顶点 W∈整数边界 → 整数
            // → g_posInvalid=0 通过；半砖/楼梯（materialID==1 的漏网形状）顶点有 0.5 偏移
            // → g_posInvalid=1 过滤（保留防"幻影整块"）。
            vec3 worldAligned = scenePos + cameraPositionFract;
            vec3 vertexPos = abs(worldAligned - round(worldAligned));
            g_posInvalid = step(0.001, vertexPos.x + vertexPos.y + vertexPos.z);
        }
        g_mcLightLevel = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));
        // at_midBlock 是 block model 空间下的方块中点；gl_Vertex 是 block model 空间下的
        // 顶点坐标。toCenter = 中点 - 顶点，方向指向 block 内部。对于 block boundary
        // 上的面（如方块底面 = 下方方块顶面），不加偏移时 centroid 落在 grid cell 边界上，
        // floor() 可能跳到相邻格子 → 体素数据写错格 → "隐形同种光源印子"（2026-08-04 根因）。
        // 乘 0.001 确保面心向内偏移 ~0.0005 格，远小于半格 → 不影响正确 cell。
        // 无偏移坐标供 GS posDiff 完整方块检测（toCenter 偏移会让 face 三条边长度
        // 都变短 ~0.001 → 总和偏离 3.4142 达 0.003+→ 检测全失败，所有默认方块被丢弃）
        // [FIX 2026-08-06 世界对齐根因] 恢复 cameraPositionFract，与 参考实现 Voxelizer/Shadow.glsl
        // 逐字一致：两端都用 (W−C)+cameraPositionFract+VOXEL_RADIUS，= W−floor(C)+VOXEL_RADIUS
        // （精确整数、与相机位置无关的世界对齐网格）。此前只在体素化端删掉 Cf 而追踪端
        // (VoxelTracing.glsl origin+=cameraPositionFract) 仍保留 → 两端差 1 格 → 追踪永远
        // 读偏真实地形（只命中形状块）。Iris shadow pass 的 cameraPositionFract 与主相机一致。
        g_voxelCoordBase = scenePos + cameraPositionFract + float(VOXEL_RADIUS);
        vec3 toCenter = at_midBlock.xyz - gl_Vertex.xyz;
        g_voxelCoord = g_voxelCoordBase + toCenter * 0.001;
    #endif
}
