//================================================================================================//
// Voxel Data — 体素追踪共享工具（照抄 参考实现 TracingUtilities.glsl / TracingNoise.glsl）
//
// - VoxelRandUnitVector / VoxelHemisphereUnitVector：均匀球面/半球采样（参考实现 语义，
//   pdf = saturate(dot(dir, normal)) * 2.0，见各调用点）
// - VoxelSphereHit / VoxelHitLightSphere：发射光球形光源（照抄 参考实现 BlockShape 的
//   SphereIntersectionLength / HitLightShpere）：光线对准球心 → 1.0，擦边 → 平滑衰减。
//   光源体素在追踪/IRC 中走此路径（平滑贡献 + 穿透不挡光），普通固体才命中停止。
// - VoxelAlbedoToAbsorption / VoxelIsTranslucentAbsorb：透明吸收（照抄 参考实现
//   AlbedoToAbsorption / isTranslucent）：水3/玻璃4/叶13 单层吸收着色，光穿透被衰减。
// - VoxelGetAtlasCoord：命中点精确图集 UV（体素数据 xy=midCoord、w=texRes 像素分辨率）。
//   当前追踪/IRC 命中改用整块中心色 texture(atlas2D, vd.xy)（64³ 网格下精确纹素
//   会把高对比纹理反弹到相邻面 → "光源印子"，2026-08-04）；本函数保留待 BlockShape
//   阶段（128³+ 网格或形状求交时才需要纹素级定位）。
//
// 依赖：调用方需先 include 并声明 uniform sampler3D voxelDataSampler 与
// uniform sampler2D atlas2D（无显式 binding，Iris 按名字自动绑定）。
//================================================================================================//

// 6 方向邻居偏移（IRC 表面判定 / 查询邻居搜索共用；与 VoxelGI.glsl 查询端局部数组同构）
const ivec3 VOXEL_DIRS[6] = ivec3[6](
    ivec3( 1, 0, 0), ivec3(-1, 0, 0),
    ivec3( 0, 1, 0), ivec3( 0,-1, 0),
    ivec3( 0, 0, 1), ivec3( 0, 0,-1)
);

// 均匀球面采样（参考实现 RandUnitVector：z 方向球坐标）
vec3 VoxelRandUnitVector(inout uint s) {
    vec2 noise = vec2(nextFloat(s), nextFloat(s));
    vec2 randAngle = vec2(TAU * noise.x, acos(2.0 * noise.y - 1.0));
    return vec3(sin(randAngle.x) * sin(randAngle.y), cos(randAngle.x) * sin(randAngle.y), cos(randAngle.y));
}

// 均匀半球采样（参考实现 HemisphereUnitVector：均匀球面采样后按法线翻转到半空间）
vec3 VoxelHemisphereUnitVector(vec3 n, inout uint s) {
    vec3 rv = VoxelRandUnitVector(s);
    return rv * (dot(rv, n) >= 0.0 ? 1.0 : -1.0);
}

float VoxelMin3(vec3 v) {
    return min(min(v.x, v.y), v.z);
}

float VoxelMax3(vec3 v) {
    return max(max(v.x, v.y), v.z);
}

// Pack2xU8 解码（照抄 参考实现 Utilities.glsl Unpack2xU8_Y_from_U16 语义，L151-154）：
// voxelData.w = Pack2xU8(texRes, skylight)（对应打包端 Shadow.frag）——
// 高 8 位 = 纹理分辨率（低配固定 16/255）、低 8 位 = 该格天空光 lightmap（0-1）。
// skylight 走 imageStore（写胜）而非 voxelLightData 的 atomicMax：max 合并会把洞内格
// 被缝隙面抬高的 sky 当整格值 → SUNLIGHT_LEAK_FIX 泄漏衰减失效；写胜语义下 w 就是
// 该方块写入时的真实 sky（参考实现 用 w 通道存 skylight 的原因，Shadow FSH 同款打包）。
// 用浮点取模代替位运算：与 参考实现 位运算版精度等价（rgba16f 的 half 存储是精度天花板，
// 两者都在 ±1/255 级舍入内），且避免部分 GLSL 语言服务对 uint 局部变量的误报。
// 参数名不能叫 packed——packed 是 GLSL 保留字（layout 限定符关键字，4.20+），
// 作参数名会导致 "abstract parameters not allowed" 编译错误。
float VoxelUnpack2xU8Y(float packedValue) {
    float scaled = packedValue * 65535.0;
    return (scaled - floor(scaled / 256.0) * 256.0) / 255.0;
}

// Pack2xU8 高 8 位解码（草方块 tint 修复）：固体格 w 高 8 位 = 染过色 albedo.B（替代固定 texRes）。
float VoxelUnpack2xU8X(float packedValue) {
    float scaled = packedValue * 65535.0;
    return floor(scaled / 256.0) / 255.0;
}

// 光线对光源球（球心=格中心，半径 VOXEL_GI_LIGHT_RADIUS，默认 1.0）的命中强度（照抄
// 参考实现 SphereIntersectionLength）：光线穿过球心 → 1.0；擦边 → 平滑衰减到 0（余弦平滑，
// 无 0/1 命中跳变——"贴着光源方块表面移动闪烁"根因：旧实现 DDA 命中发射体素 = 0/1
// 全强度开关）。弦长按半径归一化 → 0~1 与 参考实现 的 r=0.5 弦长同尺度。
// 半径放大（VOXEL_GI_LIGHT_RADIUS=1.0，2026-08-04）：提高命中率 → 平均贡献提高
//（修"走亮停灭"：TAA/IRC 收敛后火把近场平均亮度太低），相对噪声 sqrt((1-p)/p) 下降。
// rayOri = 光线起点（体素空间连续坐标）、rayDir = 单位方向、voxelCoord = 光源格坐标。
float VoxelSphereHit(vec3 rayOri, vec3 rayDir, vec3 voxelCoord) {
    vec3 centerVec = rayOri - voxelCoord - 0.5; // 起点 → 球心
    float radius = VOXEL_GI_LIGHT_RADIUS;
    float b = dot(rayDir, centerVec);
    float c = dot(centerVec, centerVec) - radius * radius;
    float d = b * b - c;
    float hit = 0.0;
    if (d > 0.0) {
        d = sqrt(d);
        hit = saturate(min(-b + d, d * 2.0) * rcp(radius));
    }
    return hit * hit;
}

// 发射光颜色表（照抄 参考实现 BlockShape.glsl LightShpereColor 思路，按材料 ID 取固定光源色）。
// 不用纹理中心 albedo：火把纹理中心是暗色木杆，发射色又暗又灰 → "光源周围黑印"
//（2026-08-04 实测）；固定暖色让火把/灯笼/萤石等发出对应颜色的亮光。
// ID 对应 block.properties #Lights 区（20-31，Shadow.geom 的 emissive 硬编码区间）。
vec3 VoxelLightColor(float voxelID) {
    if (voxelID >= 20.0 && voxelID <= 31.0) {
        int id = int(voxelID);
        if (id == 20) return vec3(0.95, 0.75, 0.50);  // 蜡烛/蛙明灯/末地烛/红石块/青金石/绿宝石
        if (id == 21) return vec3(1.00, 0.75, 0.45);  // 火把/灯笼/营火/熔炉
        if (id == 22) return vec3(1.00, 0.60, 0.30);  // 火焰
        if (id == 23) return vec3(1.00, 0.80, 0.50);  // 萤石/南瓜灯/岩浆块/菌光体
        if (id == 24) return vec3(0.75, 0.90, 1.00);  // 海晶灯/诡异菌柄/红石线
        if (id == 25) return vec3(1.00, 0.35, 0.30);  // 红石火把
        if (id == 26) return vec3(0.45, 0.80, 1.00);  // 灵魂火/灵魂火把/灵魂灯笼
        if (id == 27) return vec3(0.85, 0.65, 1.00);  // 紫水晶
        if (id == 28) return vec3(0.85, 1.00, 0.45);  // 发光浆果
        if (id == 29) return vec3(1.00, 0.50, 0.25);  // 充能铁轨/侦测器
        if (id == 30) return vec3(1.00);              // 信标
        return vec3(0.40, 0.90, 0.90);                // 31：幽匿/幽匿感测体
    }
    // [FIX 2026-08-06] 岩浆/发光地衣发射色（Shadow.geom 已把它们加入发射区）：
    // 原版方块光 lightmap 关闭后岩浆/地衣作为体素发射源照亮周围，固定暖色/绿色。
    if (voxelID == 7.0) return vec3(1.00, 0.45, 0.18);   // 岩浆
    if (voxelID == 32.0) return vec3(0.55, 0.95, 0.35);  // 发光地衣
    return vec3(1.0); // 兜底：白色（非发射体素不会走到此路径）
}

// 发射光球形光源贡献（照抄 参考实现 HitLightShpere；光源色 = VoxelLightColor 固定色表，
// VOXEL_GI_BOOST 替代 参考实现 的 BLOCKLIGHT_BRIGHTNESS 旋钮）。
// 2026-08-04 修复"光源周围黑印"：VoxelSphereHit 的弦长模型要求光线穿过格中心才强
//（hit = 弦长²），从光源周围像素/体素投出的随机光线大多擦边 → 火把光传播不出去。
// 硬保底 0.35 虽恢复传播，但让所有穿过光源格的射线一律 ≥0.35×BOOST → 光源周围出现
// 硬边亮斑（"隐形光源印子"，玩家移动时暂时正常）。改为 mix(hit,1,0.15)：
// 保留平滑空间衰减（擦边→0.15，穿心→1.0），去掉硬边；传播仍由 0.15 底保证。
// 距离衰减（#8）：远场偶发"穿心"命中闪现全强度（光能瞬移）→ 高对比可见闪烁；
// dist = 起点到球心距离，× rcp(1+dist²×VOXEL_GI_LIGHT_FALLOFF) 后远场命中大幅变弱，
// 近场 1-2 格几乎不变（dist=1 → 87%）。参考实现 用低强度脉冲（×0.1）天然降方差，
// 我们保持高强度但加距离衰减 + 追踪端单独压低（VOXEL_GI_TRACE_LIGHT_STRENGTH）。
vec3 VoxelHitLightSphere(vec3 rayOri, vec3 rayDir, vec3 voxelCoord, vec3 emissiveColor) {
    vec3 centerVec = rayOri - voxelCoord - 0.5;
    float strength = mix(VoxelSphereHit(rayOri, rayDir, voxelCoord), 1.0, 0.15);
    strength *= rcp(1.0 + dot(centerVec, centerVec) * VOXEL_GI_LIGHT_FALLOFF);
    return emissiveColor * strength * VOXEL_GI_BOOST;
}

// 透明吸收系数（照抄 参考实现 Utilities.glsl AlbedoToAbsorption）：
// 把"线性 albedo × 不透明度 alpha"映射为光线穿过后的吸收系数（1=无吸收，越小越吸收）。
// alpha=1 实色方块 → 强吸收（≈albedo×0.4）；alpha=0 镂空（树叶纹理孔洞）→ 弱吸收（≈0.7 底）。
vec3 VoxelAlbedoToAbsorption(vec3 albedo, float alpha) {
    return mix(vec3(0.7), albedo * (1.0 - alpha * 0.6), sqrt(alpha) * 0.33 + 0.67);
}

// 透明吸收判定（照抄 参考实现 isTranslucent：水3 / 玻璃4 / 树叶13）。
// 命中这些透明体素时光线做单层吸收着色后继续穿透；植物(1000-1003)/传送门(1500)纯穿透。
// absVoxelID = 体素数据 z 的绝对值（项目透明体素存负 ID，见 Shadow.vert translucent 判定）。
bool VoxelIsTranslucentAbsorb(float absVoxelID) {
    return absVoxelID > 0.5 &&
           (abs(absVoxelID - 3.0) < 0.5 || abs(absVoxelID - 4.0) < 0.5 || abs(absVoxelID - 13.0) < 0.5);
}

// 命中点精确图集 UV（照抄 参考实现 GetAtlasCoord）。
// voxelCoord = 命中体素整数坐标（float 化）；midTexCoord = 体素数据 xy（atlas UV 中心）；
// textureResolution = 体素数据 w（像素分辨率，本项目固定 16）；
// hitVoxelPos = 连续命中点（穿透式 DDA 步进中 origin + dir * rayLength）；hitNormal = 命中面法线。
vec2 VoxelGetAtlasCoord(vec3 voxelCoord, vec2 midTexCoord, float textureResolution,
                        vec3 hitVoxelPos, vec3 hitNormal) {
    vec2 atlasPixelSize = 1.0 / vec2(textureSize(atlas2D, 0));
    vec3 hitMidPos = hitVoxelPos - voxelCoord - 0.5;
    vec2 hitCoordOffset = vec2(
        hitMidPos.x * abs(hitNormal.y) - hitMidPos.z * hitNormal.x + hitMidPos.x * hitNormal.z,
        hitMidPos.y * abs(hitNormal.y) + hitMidPos.z * hitNormal.y - hitMidPos.y
    );
    hitCoordOffset = saturate(hitCoordOffset + 0.5) - 0.5;
    return midTexCoord + hitCoordOffset * atlasPixelSize * textureResolution;
}

// 方块形状求交（参考实现 BlockShape 完整版，ID 平移 +150）：IsHitBox/HitShape/IsHitBlock
// 须在 VoxelMin3/VoxelMax3 定义之后 include。
#include "/lib/lighting/VoxelShape.glsl"
