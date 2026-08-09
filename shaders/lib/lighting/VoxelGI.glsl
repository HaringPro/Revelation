//================================================================================================//
// Voxel GI — IRC 缓存内部数据访问（对齐 参考实现 语义）
//
// 参考实现 架构（对照 Soild_FS.glsl L576-585）：IRC（辐照度缓存）是**内部数据**，不直接渲染上屏。
// - 注入循环（VoxelGI.frag）每帧维护缓存
// - 每像素漫反射追踪（VoxelTracing.glsl）命中体素时，用本文件的 FetchVoxelRadiance
//   取命中点的前帧辐照度作为"自反弹种子"（对应 参考实现 DiffuseTracing_FS L569
//   SampleIrradianceCache(hitVoxelPos)）
// - DEBUG_VOXEL_RADIANCE 单点诊断（玩家相机格）
// 主 GI 由每像素追踪提供（高分辨率、无 64³ 方格），IRC 不再直接上屏。
// 坐标系与 Terrain 体素化一致：worldPos(相机相对) + cameraPositionFract + VOXEL_RADIUS
// 注意：DeferredLight.frag 在 L224 会把 worldPos 改成"伪绝对坐标"，追踪/调试在 L182 后
// 备份了确定的相机相对坐标 camRelPos。
//================================================================================================//

// 无显式 binding：与传播端一致，交由 Iris 按名字自动绑定（显式 binding 会与
// Iris 分配的普通贴图纹理单元冲突，导致采样读不到数据——"全黑"根因之一）
uniform sampler3D voxelRadianceSampler;
uniform sampler3D voxelRadiance2Sampler;
// 体素化光数据（r32ui 打包：x=emissive y=sky z=block），DEBUG_VOXEL_GI 判断光源体素用
uniform usampler3D voxelLightSampler;
// 体素数据（rgba16f：z=voxelID 原值），仅 DEBUG_VOXEL_RADIANCE 诊断用
uniform sampler3D voxelDataSampler;

// 帧奇偶采样（与注入端写入一致：偶数帧写 voxelRadiance、读 voxelRadiance2）
vec4 FetchVoxelRadiance(ivec3 c) {
    return ((frameCounter & 1) == 0)
        ? texelFetch(voxelRadiance2Sampler, c, 0)
        : texelFetch(voxelRadianceSampler, c, 0);
}
