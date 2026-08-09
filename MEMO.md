# 排查备忘录：天空贴图异常（2026-08-09）

## 问题现象

新版光影（VoxelGI 重构后）出现：

- 环境光亮度整体过低
- 缺少天空光染色，朝上的表面尤其暗
- 打开 `DEBUG_SKY_MAP` 时，左下角天空贴图只有白色方块，屏幕其余部分全黑

旧版文件夹 `旧版环境光正常` 无此问题。

## 根因

**`shaders.properties` 中存在非 ASCII 字符，导致 Iris 的配置预处理崩溃，第 278 行之后的所有配置全部丢失。**

Iris 使用 C 预处理器（jcpp）解析 `shaders.properties`。遇到 `³`、`¼`、`→`、`—` 这类特殊符号时会直接抛异常：

```text
[Render thread/ERROR] [Iris/]: Properties pre-processing failed
org.anarres.cpp.InternalException: Bad token [³@278,0]:"³"
```

配置解析中断后，丢失的关键项包括：

| 丢失的配置 | 位置 | 后果 |
|---|---|---|
| `size.buffer.colortex5 = 256 256` | 第 459 行 | 天空贴图缓冲变成全屏尺寸，GenSkyMap 只写入左下角 256×256，其余为未初始化数据 |
| `program.world0/...` 等全部程序开关 | 第 378–410 行 | GI 链路（deferred/VoxelGI）程序启停错乱 |

## 症状与根因的对应关系

- **白色方块 + 其余全黑**：`colortex5` 尺寸丢失后，`DEBUG_SKY_MAP` 按 `textureSize` 覆盖整屏；左下角 256×256 是真实天空（HDR 高亮→白），其余是未初始化数据（黑）。
- **环境光过低 / 朝上表面暗 / 缺天空染色**：球谐光（skySH）从损坏的天空贴图采样，天空 SH 全部失效。
- **场景整体更暗**：程序开关丢失导致 GI 流程错乱。

## 已做的修复

1. `shaders/shaders.properties`：所有非 ASCII 字符清理为纯 ASCII（中文注释改为英文，`—`→`--`、`→`→`->`）。
2. `旧版环境光正常/shaders/shaders.properties`：清除 `³`（`128³` → `128^3`）。
3. 保留排查期间的两处正确修复：
   - `GenSkyMap.comp` / `GenCloudShadow.comp`：棋盘条件 `(tid & 1) == offset`（bvec2 放进 if，非法 GLSL）改为 `all(equal(tid & 1, offset))`。
   - `VoxelGI.frag` / `VoxelTracing.glsl`：恢复被临时 `* 0.0` 禁用的阳光 GI 散射。

## 以后怎么避免

- **`shaders.properties` 只能写 ASCII**：不要放中文注释，更不要放 `³` `¼` `²` `→` `—` `×` `≥` 等特殊符号。
- `.glsl` 文件不受影响：`//` 注释在预处理时会被剥除，中文注释可以正常使用。
- 排查同类问题先看日志：搜索 `Properties pre-processing failed` 或 `Bad token`，几秒钟即可定位。

## 排查时间线（供复盘）

- 8/6：VoxelGI 重构（`db1034a gi改进`）在 shaders.properties 新增含 `—`、`→` 的中文注释 → 配置预处理开始崩溃。
- 8/8：误判为 SkyView LUT 派发问题，多次改 `workGroups`/`workGroupsRender`。
- 8/9：从游戏日志抓到 `Bad token [³@278,0]`，确认根因；清理非法字符后所有问题消失。

---

# 备忘：阳光 GI 移植关键点（2026-08-09）

## 阳光阴影判定（VoxelSunShadow.glsl）

移植自参考实现的 `ShadowTracing.glsl`（SimpleShadow + SimpleShadowTracing），两个函数：

- `VoxelSunShadowMap(camRelPos, normal)`：实时阴影贴图判定。**命中点必须传连续命中点（`origin + dir * rayLength`），不能传整数体素格坐标**——整数格坐标对体素化数据的逐帧更新极敏感，相机移动时 sunVis 会在 0/1 间跳变 → 阳光散射时有时无（实测踩坑）。
- `VoxelSunShadowTracing(voxelPos, sunDir)`：从命中体素向太阳走 3 格做 DDA，捕捉阴影贴图外的网格内小遮挡（屋檐/树冠/墙角）。

用法：追踪端 `sunVis = ShadowMap × ShadowTracing`，注入端 `sunVis = ShadowMap`。

## 彩色玻璃阳光反弹（shadowcolor0 alpha 通道）

实现"阳光穿过彩色玻璃 → 反弹光线染色"：

1. `Shadow.frag`：`shadowcolor0Out` 从 `out vec3` 改 `out vec4`，**a 存纹理原始不透明度**（实心 1.0、玻璃 0~1）；rgb 保持原有混合逻辑，PCSS 彩色阴影观感不变。
2. `VoxelSunShadowMap` 返回 vec3 彩色阴影：
   - shadowtex1（实心深度）被挡 → 0
   - shadowtex0（透明深度）没挡 → 1
   - 穿过玻璃 → `VoxelAlbedoToAbsorption(sRGBToLinear(颜色), 不透明度)` 得吸收色
3. 阳光反弹/注入项乘 vec3 彩色阴影。

未做：水吸收分支（当前光影水数据走 shadowcolor1，shadowcolor0 无水）。

## 移植过程中的两个编译坑

- **include 顺序**：共享文件必须在它依赖的声明之后 include。VoxelSunShadow.glsl 依赖 `DistortShadowSpace`（shadow/Common.glsl）和 `shadowtex1` 声明——VoxelGI.frag 里曾放在它们之前 → `C1503 undefined variable`。
- **sampler2DShadow 的 textureLod**：`shadowtex1` 声明为 sampler2DShadow 时，`textureLod` 要传 **vec3（xy + 参考深度）**，返回就是硬件比较结果（0/1），不要再 step；普通 sampler2D（shadowtex0）才用 `textureLod(vec2).x` 手动 step → 传 vec2 给 sampler2DShadow 会报 `C1115 unable to find compatible overloaded function`。

## 经验

- 移植参考实现时尽量照抄其坐标/参数语义（连续命中点、参考深度），不要自作主张简化成整数格或省掉转换。
- 改 shadow 缓冲输出格式前，先确认目标缓冲有没有对应通道（vec3 → vec4 需要缓冲支持 alpha）。
