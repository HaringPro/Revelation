//================================================================================================//
// Voxel GI — 配置宏（统一入口，所有体素 GI 相关文件 include 此文件）
//================================================================================================//

#ifndef VOXEL_GI_LIGHTING_INCLUDED
#define VOXEL_GI_LIGHTING_INCLUDED

#ifndef VOXEL_AREA
    #define VOXEL_AREA 64          // 体素网格边长 [32 64 128]
#endif
#ifndef VOXEL_RADIUS
    #define VOXEL_RADIUS (VOXEL_AREA / 2)
#endif

// ------ Shadow Map 平铺布局（ITRP VoxelProfile.glsl 移植）------
// 体素化迁到 shadow pass（2026-08-04）：阴影贴图拆成两块——
//   - 真阴影：右上区（宽 VOXEL_SHADOW_WIDTH = RES - TILE_WIDTH）
//   - 体素三角形：左条带（宽 VOXEL_TILE_WIDTH，Y 型平铺 64³ = 256×1024 texel）
// 太阳方向固定 → 体素化内容不随相机转动（根治 gbuffers 时代"转头/移动重播种闪烁"）。
// 布局常量跟随 shadowMapResolution（settings.glsl 滑条），要求 shadowMapResolution ≥ 1024
// （tile 高 1024 硬需求；改小会溢出挤掉真阴影）。真阴影 Shift 由 shadow GS 与
// Render.glsl 的 WorldToShadowScreenSpace 同步应用，两侧必须一致。
#ifndef VOXEL_SHADOW_RES
    #define VOXEL_SHADOW_RES float(shadowMapResolution)   // 阴影贴图总宽/高（跟随滑条）
#endif
#ifndef VOXEL_TILE_WIDTH
    #define VOXEL_TILE_WIDTH 256.0                         // 体素条带宽度（64 格 × 4 层/行）
#endif
#ifndef VOXEL_TILE_HEIGHT
    // 64³ = 262144 texel；Y 型平铺：每行 4 层 × 64 格，16 行 → 高 1024
    #define VOXEL_TILE_HEIGHT (float(VOXEL_AREA) * float(VOXEL_AREA) * float(VOXEL_AREA) / VOXEL_TILE_WIDTH)
#endif
#define VOXEL_SHADOW_WIDTH (VOXEL_SHADOW_RES - VOXEL_TILE_WIDTH)
#define VOXEL_SHADOW_RATIO (VOXEL_SHADOW_WIDTH / VOXEL_SHADOW_RES)

// 0-1 屏幕坐标 → 真阴影右上区（采样端 WorldToShadowScreenSpace 用）
void ShiftShadowScreenPos(inout vec2 coord) {
    coord = coord * VOXEL_SHADOW_RATIO + vec2(1.0 - VOXEL_SHADOW_RATIO, 0.0);
}

// NDC 坐标 → 真阴影右上区（shadow GS 发射真阴影三角形用）
void ShiftShadowNdcPos(inout vec2 coord) {
    coord = coord * VOXEL_SHADOW_RATIO + vec2(1.0 - VOXEL_SHADOW_RATIO, VOXEL_SHADOW_RATIO - 1.0);
}

// 体素网格坐标 → 平铺纹素坐标（Y 型平铺，照抄 ITRP）：
// voxelCoord.y（高度层）沿 x 摊开（每层 VOXEL_AREA 格），行号 = floor(x / TILE_WIDTH)，
// 换行时 x 回绕、z 累加层步长。输入 (x,y,z) ∈ [0,VOXEL_AREA)³，输出 (x,z) ∈ [0,TILE_WIDTH)×[0,TILE_HEIGHT)
vec2 VoxelTexel_From_VoxelCoord(vec3 voxelCoord) {
    voxelCoord.x += voxelCoord.y * float(VOXEL_AREA);
    voxelCoord.y = floor(voxelCoord.x / VOXEL_TILE_WIDTH);
    voxelCoord.xz += voxelCoord.y * vec2(-VOXEL_TILE_WIDTH, float(VOXEL_AREA));
    return voxelCoord.xz;
}
#ifndef VOXEL_GI_STRENGTH
    #define VOXEL_GI_STRENGTH 1.0  // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0] GI 整体强度
#endif
// 原版 Lightmap 混合（SSILVB_BLENDED_LIGHTMAP 同款滑条，供 DeferredLight 查询端使用）：
// 1.0=完全保留原版 Lightmap（环境光+方块光），0.0=完全屏蔽原版，间接光照仅由体素 GI 提供。
// 主定义在 settings.glsl 的 Global Illumination 区（Iris 滑条直接改写），此处仅作兜底。
#ifndef VOXEL_GI_BLENDED_LIGHTMAP
    #define VOXEL_GI_BLENDED_LIGHTMAP 1.0 // [0.0 0.01 0.02 0.05 0.07 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0] 原版 Lightmap 混合（1.0=保留，0.0=屏蔽，仅 GI）
#endif

// ------ 传播配置（ITRP 风格 IRC 随机注入）------
#define VOXEL_GI_SELF_BOUNCE 0.5       // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8] 自反弹衰减比（光线命中点取前帧 IRC）
#define VOXEL_GI_EMISSIVE_THRESHOLD 0.1 // [0.0 0.01 0.02 0.05 0.1 0.2] 发射度阈值（LabPBR 发射贴图，太低会把矿物误判为发光体）
#define VOXEL_GI_BOOST 1.5              // [0.5 1.0 1.5 2.0 3.0 4.0] 发射体素能量倍率
// 发射光球形光距离衰减（照抄 ITRP 语义的补充，2026-08-04 #8）：远场（16 格外）偶发
// "穿心"命中会闪现全强度 → 高对比可见闪烁；× rcp(1 + dist²×FALLOFF) 后远场命中大幅
// 变弱（dist=8 → 9%），近场 1-2 格几乎不变。只影响球形光路径（发射体素），普通固体
// 命中/IRC 自反弹不受影响。
#define VOXEL_GI_LIGHT_FALLOFF 0.1 // [0.02 0.05 0.08 0.1 0.15 0.2 0.3 0.5] 发射光距离衰减（越小传播越远）
// 发射光球形光源半径（体素格数）。ITRP 用 0.5（格内切球），但那是多 SPP + ×0.1 低强度
// 的物理尺度；本项目 1 SPP 低配，球太小 → 贴光源面命中率极低（1 格外 ≈2.8%）→
// 平均贡献 = 命中率 × 强度 很低 → "走起来亮（TAA 运动降权显示单帧命中）、停下来灭
//（TAA/IRC 收敛到低平均值）"。放大半径：命中率 ~4-8 倍 ↑、平均亮度同升、相对噪声
// （sqrt((1-p)/p)）降 ~2-3 倍。半径 >0.5 即光晕溢出相邻格 = 物理合理（光源近场光晕）。
#define VOXEL_GI_LIGHT_RADIUS 1.0
// 追踪端发射光强度（ITRP 架构：发射光主体由 IRC 时域累积承载——IRC 注入端用
// VOXEL_GI_BOOST 强注入、时间混合 0.99 平滑；追踪端是每像素每帧 1 条随机光线的
// 高方差采样，发射光脉冲必须压低，否则贴光源面"命中/未命中"跳变 → 闪烁）。
// ITRP DiffuseTracing 里 HitLightShpere × BLOCKLIGHT_BRIGHTNESS=0.1（脉冲 0~0.1），
// 我们的追踪端脉冲 = 0.225~1.5（BOOST 1.5）→ 方差高 2 个数量级。此系数把追踪端
// 脉冲压到 ~0.07~0.45（仍高于 ITRP 的低配亮度），近场火把光主体依赖 IRC。
#define VOXEL_GI_TRACE_LIGHT_STRENGTH 0.3
#define VOXEL_GI_BLEND 0.99             // [0.5 0.6 0.7 0.8 0.9 0.95 0.98 0.99] 时间混合权重
// 注：IRC 是随机采样注入（每体素每帧 1 条光线），靠时域累积降噪。
// 0.99 = ITRP 默认（PT_IRC_BLENDWEIGHT 0.99），IRC 存"表面体素辐照度"变化慢，
// 时域稳定；首次进入场景由"旧帧全黑 → 直接写新值"播种（VoxelGI.frag），不会冷启动黑屏。
// 太低（0.6）时域噪声明显；相机移动时由整数重投影补偿，0.99 无鬼影。

// ------ IRC 随机注入参数（随 VOXEL_GI_STRENGTH 整体缩放，不单独暴露滑条）------
#define VOXEL_IRC_SPP 1                 // 每体素每帧投光线数（随机采样，时域累积等效提升 SPP）
#define VOXEL_IRC_TRACE_DISTANCE 16     // 光线最大步进体素数（64³ 网格内足以跨过洞穴/房间）
// 新暴露格天空播种倍率（ITRP PT_IRC_INITIAL_SKYLIGHT 思路）：相机移动时 64³ 前缘
// 新进入网格的固体格 pValid=false，旧实现直接用裸 1-SPP 随机样本当初值 → 移动时
// 前缘一圈格子每帧随机闪（且 0.99 混合要 ~100 帧才收敛）。播种平滑天空值消除该闪烁。
#define VOXEL_IRC_EDGE_SEED 0.35        // 0-1 尺度（× skyColor；白天 ≈ 0.1 级注入，等效合理环境光）

// ------ 注入内部系数（随 VOXEL_GI_STRENGTH 整体缩放，不单独暴露滑条）------
// 天空光用 0-1 尺度的 skyColor，系数即注入上限（白天暴露面 ≈ 0.1×albedo）。
// 量级链路：注入 nRC → ×100 存储 → 查询 ×0.01 解码，最终 ≈ 注入值 × albedo × STRENGTH
// 2026-08-04 真阳光改造（照抄 ITRP 思路）：阳光注入主体改为"阴影贴图判定直射"（sunVis），
// vanilla 天空光 lightmap 降级为弱环境底，保留洞穴渐变。
#define VOXEL_GI_SUN_STRENGTH 0.5      // 真阳光直射注入倍率（× sunLight 暖阳色，2026-08-06 对齐 ITRP sunLight 后提亮，让阳光反弹传播到阴影）
#define VOXEL_GI_SKY_STRENGTH 0.15    // 环境天空注入倍率（× skyColor × 天空 lightmap，弱底/洞穴渐变）
#define VOXEL_GI_BLOCK_STRENGTH 0.8    // 方块光注入倍率（× blocklightColor，火把等光源）
// [FIX 2026-08-06] 方块光反弹的最小 albedo 底：薄片/流体光源（发光地衣、岩浆）的
// voxelData 中心色 midCoord 采样可能为 0/很暗（贴图大部分透明黑）→ albedo 乘进
// blocklight 后趋 0 → 光源不发光。给 blocklight 反弹一个不依赖采样色的最小 albedo。
#define VOXEL_GI_BLOCK_MIN_ALBEDO 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] 方块光反弹最小 albedo 底
// NOLIGHT 兜底（ITRP NOLIGHT_BRIGHTNESS 思路）：命中固体/出界外的闭塞处底光，
// 洞穴深处不黑死。ITRP 默认 7e-6 是物理尺度（白天物理辐照度 ~300），
// 本项目 0-1 尺度（skyColor 白天 ~0.1 级注入），等效底光取 0.0005（可调）。
#define VOXEL_NOLIGHT_BRIGHTNESS 0.0005

// ------ 每像素漫反射追踪参数（阶段③，随 VOXEL_GI_TRACE 开关生效）------
// [FIX 2026-08-05] 默认 24 → 32：用户反馈"光线传播距离太短"，加大追踪最大步进让
// 阳光反弹/方块光能传更远；已暴露为 GUI 滑条。
#define VOXEL_TRACE_DISTANCE 32 // [8 16 24 32 48 64 96] 追踪光线最大步进体素数（越大传播越远，性能略降）
// 追踪 GI 强度总旋钮：信号量级 = 追踪值 × STRENGTH（命中/出界已按 ITRP 语义全强度输出，
// 过亮就降这个，过暗就升；洞穴不过量由 lightmap 泄漏衰减保证，不靠压低天空值）。
#define VOXEL_GI_TRACE_STRENGTH 1.0
// 物理直射辐照度 → 0-1 尺度换算参考（GlobalStorage.comp：directIlluminance = 128×(sun+moon)，
// 白天约 300；除以本参考即得 0-1 尺度阳光色——自带昼夜明暗 + 暖色温，见 VoxelTracing 阳光弹射）
#define VOXEL_SUN_REFERENCE 300.0
// 追踪端阳光弹射强度（ITRP sunLight = colorShadowlight，无额外小系数；阴影贴图判定直射）。
// 命中体素朝向太阳时 sunVis=1 → 阳光色×1.0×albedo（反射率级），被遮挡时 0。
// 2026-08-05：阳光色已从 skyColor（天空蓝环境色，与出界天空路径同色 → 反弹看不出来）
// 改为物理直射辐照度换算；强度 1.0 → 2.0 让反弹在阴影里可辨。
// [FIX 2026-08-05] 2.0 → 8.0：阳光项去掉 rPI 后仍比方块光弱，实测"阳光反弹不可见"；
// 8.0 让阳光反弹 ≈ 0.4×cosθ×albedo×8 达到可见量级（过亮可调回 2-5）。
// 已暴露为 GUI 滑条（shaders.properties sliders），可在光影设置里直接调。
#define VOXEL_TRACE_SUN_STRENGTH 8.0 // [0.0 0.5 1.0 2.0 3.0 5.0 8.0 12.0 16.0 24.0 32.0] 追踪端阳光反弹强度
// 追踪端出界天空（对齐 ITRP SkyLighting 语义：出界 = skyColor × pdf × lightmap 衰减，无 0.05
// 小系数——ITRP 正是靠 lightmap 衰减防室内漏光，不是靠压低天空值）。
// 户外（skyLightmap≥0.23）全开：开阔地面出界光线 ≈ skyColor×dir.y×weight（白天可见方向性天光）；
// 洞穴/室内被 sat(skyLightmap*4.44) 压到 0，不会过量。若整体过亮用 VOXEL_GI_TRACE_STRENGTH 旋钮。
#define VOXEL_GI_TRACE_SKY_STRENGTH 1.0
// （新增环境光控制宏已移除 2026-08-06：环境光还原旧版纯 skySH 行为）

#endif // VOXEL_GI_LIGHTING_INCLUDED
