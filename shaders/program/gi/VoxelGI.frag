/*
--------------------------------------------------------------------------------
    Revelation Shaders — Voxel GI 辐照度缓存（IRC 随机注入，ITRP 架构移植 · 阶段②）
    Copyright (C) 2026 HaringPro

    照抄 ITRP IRC_CS 语义：
    - 只对非空气体素注入（表面/内部固体都投光），空气体素 alpha=1 标记遮挡不注入
    - 表面判定（ITRP sampleHemisphere）：恰好 1 空邻居 + 非普通方块（abs(ID)>1，
      岩浆/光源等特殊方块）→ 起点沿空邻居方向偏移半格到表面 + 半球采样
      pdf=saturate(dot(dir,n))*2.0；其余（普通实心/内部固体/多空邻居）→ 全方向 pdf=1.6
    - 穿透式 DDA 增量步进判定命中（照抄 ITRP IRC_CS L199/L297/L301 语义）：
      空气/透明（z<=0.5）→ 穿透；发射光体素（lD.x>阈值）→ 球形光源平滑贡献
      + 穿透不挡光（照抄 HitLightShpere）；普通固体才命中停止，其中形状块
      （155-294，楼梯/门/栅栏等，照抄 ITRP BlockShape IsHitBlock）先做子盒
      求交，穿过子盒空隙则继续步进
    - 命中：方块光 + 真阳光（rPI 方向项 × 命中体素 lightmap 平滑衰减，
      无阴影贴图硬判定——体素中心单点比较在阴影边缘 0/1 跳变会块状闪烁）
      + 自反弹（前帧 IRC，带整数重投影）
    - 起点自发光（照抄 ITRP IRC_CS L196-200）：发射体素先把自己的球形光加进结果，
      否则火把格自身 IRC 为暗 → 追踪端反弹火把格得暗值 → "光源周围黑印"
    - 发射色 = VoxelLightColor 材料 ID 固定色表（火把暖黄），不用暗色纹理 albedo
    - 出界：skyColor 方向性天空 × SUNLIGHT_LEAK_FIX 衰减（×当前体素天空光，防洞穴漏光）
    - ×100 内部存储 / ×0.01 外部采样（voxelRadiance / voxelRadiance2 ping-pong）
    - 时间混合：IRC 是随机采样，靠时域累积降噪（VOXEL_GI_BLEND=0.99，ITRP PT_IRC_BLENDWEIGHT）
    - 相机移动时前帧坐标重投影（cDi = cameraPositionInt - previousCameraPositionInt）
--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Config //==============================================================================//

#include "/config.glsl"

//======// Uniform //=============================================================================//

// 全部不写 layout(binding=N)：显式 image binding 与 Iris 运行时分配的
// 普通贴图纹理单元同处一套硬件单元，会冲突导致 imageStore/imageAtomic 静默失效
// （"整个世界全黑"根因）。照抄 ITRP：无 binding，靠 shaders.properties 的
// image.<name> = <samplerName> 让 Iris 按名字自动绑定。
uniform sampler3D voxelRadianceSampler;
uniform sampler3D voxelRadiance2Sampler;

layout (rgba16f) writeonly uniform image3D voxelRadiance;
layout (rgba16f) writeonly uniform image3D voxelRadiance2;

uniform usampler3D voxelLightSampler;
// 体素数据（rgba16f）：xy=atlas UV 中心、z=voxelID(原值,>0 固体)、w=texRes(16)
uniform sampler3D voxelDataSampler;
// 方块图集（shaders.properties customTexture.atlas2D = blocks.png，与 gbuffers 的 tex 同图集）
uniform sampler2D atlas2D;

// 体素化缓冲（voxelData / voxelLightData）每帧由 begin1（VoxelClear.comp）
// 在 shadow pass 前清空，体素化已迁到 shadow pass（太阳固定，不随相机转动），
// 传播 pass 只读不写，稳定读到本帧完整数据

#include "/lib/universal/Uniform.glsl"

// 随机数（triple32 / nextFloat 等）；必须放在 Uniform.glsl 之后（用到 noisetex 等 uniform）
#include "/lib/universal/Random.glsl"

//======// Settings //============================================================================//

#include "/lib/lighting/VoxelLighting.glsl"

// 共享体素追踪工具（Ray/DDA/半球采样/GetAtlasCoord，照抄 ITRP TracingUtilities）
#include "/lib/lighting/VoxelData.glsl"

//======// 阴影变换（sunDir 方向项用 shadowModelViewInverse）//=================================//

#include "/lib/lighting/shadow/Common.glsl"

//======// Helper //==============================================================================//

// 读取上一帧辐照度（ping-pong 由帧奇偶决定），×0.01 解码内部 ×100 缩放
vec3 FetchPrevRadiance(ivec3 c) {
    if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(VOXEL_AREA)))) return vec3(0.0);
    return ((frameCounter & 1) == 0
        ? texelFetch(voxelRadiance2Sampler, c, 0)
        : texelFetch(voxelRadianceSampler, c, 0)).rgb * 0.01;
}

// 天空光颜色：用 0-1 尺度的 skyColor（自带昼夜/日出日落着色）。
// 注意：不能用 global.skyUpIlluminance —— 它是 ×128 的物理辐照度（白天约 300），
// 用它做注入会让洞穴整体爆亮（实测教训）。
vec3 VoxelSkyColor() {
    return skyColor;
}

// 单个体素的 IRC 随机注入（照抄 ITRP IRC_CS 语义）：
// - 表面判定（ITRP sampleHemisphere）：恰好 1 个空邻居（z<=0.5：空气/负 ID 透明体素）
//   + 当前体素是"特殊方块"（abs(voxelID)>1，非普通实心块 ID=1）→ 半球采样：
//   起点沿空邻居方向偏移半格到表面，法线背离空侧，pdf = saturate(dot(dir,n))*2.0；
//   其余（普通实心 / 内部固体 / 多空邻居）→ 全方向均匀（pdf=1.6）
// - DDA 增量步进判定命中：
//   出界/射程用尽 → 天空（方向性衰减 × SUNLIGHT_LEAK_FIX：×当前体素天空光，
//   露天全开、洞穴/闭塞处把漏进来的天光压掉）
//   命中固体 → 发射光 + 方块光 + 真阳光（rPI 方向项 × 阴影判定）+ 自反弹 + NOLIGHT 兜底
// - 透明体素（负 ID）自动穿透（DDA 判空 z>0.5 只挡正 ID 固体）
// c = 当前体素坐标；cDi = 相机重投影；返回 0-1 空间累计值（未 ×100、未时间混合）。
vec3 IrcTraceVoxel(ivec3 c, ivec3 cDi) {
    // 每帧换种子（triple32 为完美整数哈希；frameCounter+1 避免第 0 帧全 0 种子）
    uint seed = triple32(uint(c.x + c.y * VOXEL_AREA + c.z * VOXEL_AREA * VOXEL_AREA) * 0x9E3779B1u
                         + uint(frameCounter + 1) * 0x85EBCA77u);

    vec3 result = vec3(0.0);
    vec3 voxelPos = vec3(c) + 0.5;
    // 世界空间太阳方向（shadowModelViewInverse 为纯旋转矩阵，第三行=第三列）
    vec3 sunDir = mat3(shadowModelViewInverse) * vec3(0.0, 0.0, 1.0);

    // ---- 表面判定（ITRP sampleHemisphere）----
    // 计数 6 邻居中的空体素（z<=0.5：空气或负 ID 透明），并累加指向空邻居的方向。
    // 恰好 1 个空邻居 = 该体素是一面"表面"；sampleOffset 指向唯一空侧。
    int emptyCount = 0;
    vec3 sampleOffset = vec3(0.0);
    for (int i = 0; i < 6; ++i) {
        ivec3 nc = c + VOXEL_DIRS[i];
        if (any(lessThan(nc, ivec3(0))) || any(greaterThanEqual(nc, ivec3(VOXEL_AREA)))) continue;
        if (texelFetch(voxelDataSampler, nc, 0).z <= 0.5) {
            ++emptyCount;
            sampleOffset += vec3(VOXEL_DIRS[i]);
        }
    }
    // ITRP：sampleHemisphere = hasVoxel.x==1 && hasCurrVoxel==0
    //（恰 1 空邻居 && 当前体素非普通方块，ITRP 用 abs(ID)>240 判"普通"）。
    // 本项目普通实心块 = ID 1（block.properties 未列出的方块均归一）；特殊方块
    //（岩浆 7 / 光源 20-31 等正 ID≠1）→ 半球采样；透明块（负 ID）不进入本函数
    //（main 的 sld 判定已排除）。
    vec4 currVoxelData = texelFetch(voxelDataSampler, c, 0);
    float currID = currVoxelData.z;
    bool sampleHemisphere = emptyCount == 1 && abs(currID) > 1.0;
    // ITRP：sampleOffset 累加指向 ordinary(close) 邻居，hitNormal=-sampleOffset 即
    // 朝向空旷/特殊邻居。本项目累加指向 empty 邻居 → surfaceNormal=+sampleOffset
    // 即朝向空旷侧（同 ITRP 语义："背离固体、朝向空旷"）。
    // 旧 bug：-sampleOffset 把半球投向固体侧 → 火把光打入墙/地板（房间暗）、
    // 半砖半球对着邻居固体 → 捕获邻居 IRC（含扩散火光 → 假亮），移动时网格重置
    // 新鲜播种绕过偏差，静止时偏差累积（VOXEL_GI_BLEND=0.99）。
    vec3 surfaceNormal = sampleOffset;
    if (sampleHemisphere) voxelPos += sampleOffset * 0.49999;

    // 当前体素光数据（curEmissive = 起点本身是发射体素 → 起点自发光贡献，ITRP IRC_CS
    // L196-200；hitSkylight = SUNLIGHT_LEAK_FIX 的泄漏衰减用值：本项目 DDA 对透明体素
    // 直接穿透、无中间命中记录，出界衰减用起点体素自己的天空光即可）
    vec4 curLight = unpackUnorm4x8(texelFetch(voxelLightSampler, c, 0).r);
    // hitSkylight 改从 voxelData.w 解（ITRP Unpack2xU8_Y_from_U16，VoxelData.glsl）：
    // voxelData.w = Pack2xU8(texRes, skylight)（Shadow.frag 打包），imageStore 写胜语义
    // ——修 voxelLightData.R 的 atomicMax max 合并：洞内格被缝隙面抬高的 sky 会让泄漏
    // 衰减失效（该压的没压）。curEmissive 仍读 lightData（emissive 取整格最大是正确语义）。
    float hitSkylight = VoxelUnpack2xU8Y(currVoxelData.w);
    bool curEmissive = curLight.z > VOXEL_GI_EMISSIVE_THRESHOLD;  // 新字节序：B=emissive

    for (int s = 0; s < VOXEL_IRC_SPP; ++s) {
        // 随机方向 + 对应 PDF（ITRP 归一化系数：半球 2·dot、全方向 1.6）
        vec3 dir;
        float pdf;
        if (sampleHemisphere) {
            dir = VoxelHemisphereUnitVector(surfaceNormal, seed);
            pdf = saturate(dot(dir, surfaceNormal)) * 2.0;
        } else {
            dir = VoxelRandUnitVector(seed);
            pdf = 1.6;
        }
        float rcpPdf = rcp(pdf);

        // ---- 穿透式 DDA 步进（照抄 ITRP IRC_CS L292-330：发射光体素 → 球形光源
        // 平滑贡献 + 穿透不挡光；普通固体命中停止）----
        vec3 hvoxel = floor(voxelPos);
        vec3 hsdir = sign(dir);
        vec3 hrdir = 1.0 / max(abs(dir), vec3(1e-8));
        vec3 htotalStep = (hsdir * (hvoxel - voxelPos + 0.5) + 0.5) * hrdir;
        bool exitGrid = false;
        bool hitSolid = false;
        vec3 contrib = vec3(0.0);
        // 透明吸收累积（ITRP hitSurface）：首次命中水/玻璃/树叶时着色衰减，其后贡献全乘此系数
        vec3 absorption = vec3(1.0);
        bool traceTranslucent = true;
        // 起点自发光贡献（照抄 ITRP IRC_CS L196-200：发射体素先把自己的球形光加进结果）。
        // 缺这段时发射格（火把格）自身 IRC 不含自己的光 → 追踪端反弹该格取到暗值
        // → "光源周围黑印 / 隐形光源印子"（2026-08-04 实测）。voxelPos 已按表面判定
        // 偏移，球形测试对半球采样落在表面上、全方向采样在格心，均有正向命中。
        if (curEmissive) {
            contrib += VoxelHitLightSphere(voxelPos, dir, vec3(c), VoxelLightColor(abs(currID))) * absorption;
        }
        float rayLen = 0.0;
        ivec3 hit = ivec3(0);

        for (int i = 0; i < VOXEL_IRC_TRACE_DISTANCE; ++i) {
            rayLen = VoxelMin3(htotalStep);
            vec3 tracingNext = step(htotalStep, vec3(rayLen));
            hvoxel += tracingNext * hsdir;
            htotalStep += tracingNext * hrdir;
            if (rayLen > float(VOXEL_IRC_TRACE_DISTANCE)) break;

            if (any(lessThan(hvoxel, vec3(0.0))) || any(greaterThanEqual(hvoxel, vec3(VOXEL_AREA)))) {
                exitGrid = true;
                break;
            }

            ivec3 hc = ivec3(hvoxel);
            vec4 hvd = texelFetch(voxelDataSampler, hc, 0);
            // 判空：voxelID 原值整数（>0 即固体，0=空气/负 ID 透明）
            if (hvd.z <= 0.5) {
                // 透明体素：水/玻璃/树叶单层吸收着色（ITRP isTranslucent，只吸收一次；
                // 植物/传送门纯穿透）。hvd.xy = 图集中心 UV，采样取方块颜色与不透明度。
                if (traceTranslucent && VoxelIsTranslucentAbsorb(abs(hvd.z))) {
                    vec4 tc = texture(atlas2D, hvd.xy);
                    absorption *= VoxelAlbedoToAbsorption(tc.rgb, tc.a);
                    traceTranslucent = false;
                }
                continue;
            }

            vec3 lD = unpackUnorm4x8(texelFetch(voxelLightSampler, hc, 0).r).rgb;

            if (lD.z > VOXEL_GI_EMISSIVE_THRESHOLD) {  // 新字节序：B=emissive
                // 发射光体素：球形光源平滑贡献（光线对准球心才强，擦边平滑衰减——
                // 修 0/1 命中跳变）+ 穿透继续（光源不阻挡光线，ITRP 语义）。
                // 发射色按材料 ID 查固定光源色表（VoxelLightColor）：火把纹理中心是
                // 暗色木杆，用 albedo 当发射色又暗又灰（"光源周围黑印"主因之一）。
                vec3 albE = VoxelLightColor(abs(hvd.z));
                contrib += VoxelHitLightSphere(voxelPos, dir, vec3(hc), albE) * absorption;
                continue;
            }

            // ---- 普通固体命中：形状求交（ITRP IsHitBlock 桥接）----
            // 全块（voxelID<=154，含熔岩/发光/反光）：整格命中，法线 = -tracingNext*sdir；
            // 形状块（155-294，楼梯/门/栅栏/墙…）：HitShape 子盒判定，光线穿过子盒
            // 空隙（未命中）→ 继续步进（穿透式 DDA 语义）。hitNormal 由 IsHitBlock 输出。
            VoxelRay vray;
            vray.ori = voxelPos;
            vray.dir = dir;
            vray.rdir = hrdir;
            vray.sdir = hsdir;
            vec3 hitNormal;
            bool shapeHit = IsHitBlock(vray, htotalStep, tracingNext, hvoxel, abs(hvd.z), rayLen, hitNormal);
            if (!shapeHit) continue;

            // 反弹 albedo 用整块图集中心色：64³ 网格无法表达 16px 纹理细节，
            // 精确纹素采样会把高对比纹理（如哭泣黑曜石的亮紫像素）反弹到相邻面
            // → "又贴了一块黑曜石在旁边"的印子；中心色 = 该体素平均反照率。
            hit = hc;
            vec3 alb = texture(atlas2D, hvd.xy).rgb;

            // 方块光兜底（仅非发射光源体素，避免白色方块光盖掉彩色发射色）
            if (lD.y > 0.01)  // 新字节序：G=blocklight
                contrib += alb * blocklightColor * lD.y * VOXEL_GI_BLOCK_STRENGTH * absorption;
            // 真阳光：rPI 方向项（hitNormal 为命中面法线）× 命中体素天空 lightmap
            // 平滑衰减（SUNLIGHT_LEAK_FIX；不用阴影贴图硬判定，避免阴影边缘 0/1 跳变）
            float sunLighting = saturate(dot(sunDir, hitNormal)) * rPI * saturate(lD.x * 444.0);  // 新字节序：R=sky
            contrib += alb * VoxelSkyColor() * (sunLighting * VOXEL_GI_SUN_STRENGTH
                                                + lD.x * VOXEL_GI_SKY_STRENGTH) * absorption;
            // 自反弹：前帧 IRC 在命中点的值（相机重投影；FetchPrevRadiance 内含 ×0.01 解码）
            contrib += alb * FetchPrevRadiance(hit + cDi) * VOXEL_GI_SELF_BOUNCE * absorption;
            hitSolid = true;
            break;
        }

        if (!hitSolid) {
            // 出界或射程用尽 → 天空 + NOLIGHT 兜底（照抄 ITRP IRC_CS L402/L514-515）：
            // 天空 × sat(hitSkylight * 4.44)（SUNLIGHT_LEAK_FIX 阈值 0.23，与追踪端同口径；
            // 半砖/室内微光格 lD.y≈0.1-0.2 时压到 ~0，露天全开）。注意：之前误用
            // sat(hitSkylight*2-1)（阈值 0.5）——那是 ITRP 的 PT_IRC_INITIAL_SKYLIGHT
            // 播种阈值，不是出界天空衰减阈值，且与追踪端不一致（两端口径必须统一）。
            contrib += VoxelSkyColor() * saturate(dir.y * 2.0 + 0.3)
                     * saturate(hitSkylight * 4.44) * absorption;
            // NOLIGHT 底光（ITRP 出界路径专有：NOLIGHT_BRIGHTNESS * saturate(rayLength*0.2)；
            // 命中路径无此项，闭塞处底光由自反弹/方块光链路提供）
            contrib += vec3(0.97, 0.99, 1.18) * VOXEL_NOLIGHT_BRIGHTNESS
                     * saturate(rayLen * 0.2) * absorption;
        }
        result += contrib * rcpPdf;
    }

    return result * rcp(float(VOXEL_IRC_SPP));
}

//======// Main //================================================================================//

/* RENDERTARGETS: 15 */
out vec4 dummyOut;

void main() {
    ivec2 pix = ivec2(gl_FragCoord.xy);

    // 每个屏幕像素分摊处理若干连续体素（IRC 网格 = 64³，同 voxelRadiance 双缓冲）
    int totalVoxels = VOXEL_AREA * VOXEL_AREA * VOXEL_AREA;
    int totalPixels = int(viewWidth) * int(viewHeight);
    int perPixel = max((totalVoxels + totalPixels - 1) / totalPixels, 1);
    int pixIdx = pix.y * int(viewWidth) + pix.x;
    int ia = min(pixIdx * perPixel, totalVoxels);
    int ib = min(ia + perPixel, totalVoxels);

    // 整数相机重投影（照抄 ITRP：cameraPositionInt - previousCameraPositionInt）。
    // 世界对齐网格中，相机仅移动整数格时内容整体平移，用整数差值补偿回读位置；
    // 小数移动不移动网格（cameraPositionFract 已抵消），因此不能用 float 差值取整。
    ivec3 cDi = cameraPositionInt - previousCameraPositionInt;

    // 时间混合权重：IRC 随机采样靠时域累积降噪（0.99=每帧接受 1% 新值，ITRP PT_IRC_BLENDWEIGHT）
    float bw = 1.0 - (1.0 - VOXEL_GI_BLEND) * saturate(frameTime / 0.01666667);
    // 前 2 帧 pRC 读的是未初始化缓冲（可能是垃圾大值），跳过混合直接写采样值，
    // 避免"首帧大值被每帧 ×0.9 稀释"造成视觉上逐渐变黑的假象
    if (frameCounter < 2) bw = 0.0;

    for (int vi = ia; vi < ib; ++vi) {
        int z = vi / (VOXEL_AREA * VOXEL_AREA);
        int y = (vi / VOXEL_AREA) % VOXEL_AREA;
        int x = vi % VOXEL_AREA;
        if (z >= VOXEL_AREA) break;
        ivec3 c = ivec3(x, y, z);

        #ifdef VOXEL_GI_ENABLED

        // ---- 当前帧体素数据（begin1 已在 shadow 前清空，shadow pass 写入本帧数据）----
        vec4 vd = texelFetch(voxelDataSampler, c, 0);
        bool sld = vd.z > 0.5; // voxelID 原值（>0 即固体，0=空气）

        // blocker：1=空（查询端半权重参与），0=固体
        float blk = sld ? 0.0 : 1.0;

        // ---- IRC 随机注入（照抄 ITRP：只对非空气体素注入）----
        // ITRP 语义：IRC 网格存"体素表面辐照度"，空气体素 alpha=1 标记遮挡、不注入。
        // 表面/内部固体都投光，采样方向与 PDF 由 IrcTraceVoxel 内部按 ITRP 表面判定
        // 选择（恰 1 空邻居 + 特殊方块 → 半球；否则全方向）。空体素不注入
        //（旧实现：空体素全方向注入 = "空气辐照度场"，查询端被空气邻居稀释 → GI
        // 看不见，语义与 ITRP 完全不同）。
        vec3 nRC = vec3(0.0);
        if (sld) {
            nRC = IrcTraceVoxel(c, cDi);
        }

        // ---- 上一帧辐照度（带相机重投影）----
        // 越界 = 旧帧网格未覆盖的新区域（相机移动新暴露的地形），旧帧没有有效值，
        // 若按 0 混合会把值拉低 10 倍，且自反弹反馈连锁 → 移动时越走越黑（实测）。
        // 直接采用本帧采样值（等价 bw=0），等下一帧旧帧有数据后再恢复时间混合。
        ivec3 prevC = c + cDi;
        bool pValid = all(greaterThanEqual(prevC, ivec3(0))) && all(lessThan(prevC, ivec3(VOXEL_AREA)));
        // ITRP PT_IRC_INITIAL_SKYLIGHT：新暴露的**固体**格用平滑天空值播种（见
        // VoxelLighting.glsl VOXEL_IRC_EDGE_SEED），而不是裸 1-SPP 随机样本——
        // 裸样本每帧随机（亮/暗乱跳）且 0.99 混合要 ~100 帧才收敛 = "移动噪声前沿"，
        // 播种天空值让前缘格从一开始就稳定；空气格保持 0（不写入无用值）。
        vec3 pRC = pValid ? FetchPrevRadiance(prevC)
                          : (sld ? VoxelSkyColor() * VOXEL_IRC_EDGE_SEED : nRC);

        // 旧帧全黑（冷启动 / 相机大幅移动新暴露）→ 直接写本帧值（等价 bw=0）。
        // 0.99 混合下每帧仅接受 1% 新值，若无此播种首次进入场景会黑屏 100+ 帧
        //（ITRP PT_IRC_INITIAL_SKYLIGHT 思路：缓存全黑时跳过混合播种）。
        float localBw = bw;
        if (pValid && max(max(pRC.r, pRC.g), pRC.b) < 1e-4) localBw = 0.0;

        // ---- 时间混合（实体/空体素统一；IRC 随机采样靠时域累积降噪）----
        nRC = max(mix(nRC, pRC, localBw), 1e-7);

        // ---- 保色压缩：任一分量 >1.0 时按最大分量整体缩放，保持色相不漂白 ----
        float maxC = max(max(nRC.r, nRC.g), nRC.b);
        if (maxC > 1.0) nRC *= 1.0 / maxC;

        // ---- 写入 ×100 ----
        vec4 o = vec4(nRC * 100.0, blk);
        if ((frameCounter & 1) == 0)
            imageStore(voxelRadiance, c, o);
        else
            imageStore(voxelRadiance2, c, o);

        #endif
    }

    dummyOut = vec4(0.0);
}
