//================================================================================================//
// Voxel GI — 体素辐照度传播（已废弃，保留宏兼容）
//
// 传播逻辑已迁移到 IRCPropagate.comp（计算着色器）。
// 此文件仅保留旧宏定义以保证 shaders.properties/settings 编译通过。
//================================================================================================//

#include "/lib/lighting/VoxelLighting.glsl"

#ifndef VOXEL_GI_PROPAGATE_INCLUDED
#define VOXEL_GI_PROPAGATE_INCLUDED

// 旧宏向后兼容（新 IRCPropagate.comp 不再使用）
#ifndef VOXEL_GI_MODE
    #define VOXEL_GI_MODE 1
#endif
#ifndef VOXEL_GI_RAYS
    #define VOXEL_GI_RAYS 4
#endif
#ifndef VOXEL_GI_RAY_STEPS
    #define VOXEL_GI_RAY_STEPS 8
#endif
#ifndef VOXEL_GI_DECAY
    #define VOXEL_GI_DECAY 0.9
#endif
#ifndef VOXEL_GI_FLOOD_STEPS
    #define VOXEL_GI_FLOOD_STEPS 4
#endif
#ifndef VOXEL_GI_DIR_SAMPLES
    #define VOXEL_GI_DIR_SAMPLES 4
#endif
#ifndef VOXEL_GI_DIR_DIST
    #define VOXEL_GI_DIR_DIST 4.0
#endif

#endif // VOXEL_GI_PROPAGATE_INCLUDED
