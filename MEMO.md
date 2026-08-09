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
