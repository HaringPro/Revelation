//================================================================================================//
// Voxel Shape — 方块形状求交（照抄 ITRP BlockShape.glsl 完整版，ID 平移 +150）
//
// ITRP 形状 ID 5-144 平移 +150 → 本项目形状 ID 155-294（block.properties 写作
// block.10155-10294，Shadow.vert materialID = mc_Entity.x - 1e4 = 155-294）。
// 平移避开了项目现有材料 ID：1 普通实心 / 3 水 / 4 玻璃 / 7 熔岩 / 13 树叶 /
// 20-31 发光 / 50 反光 / 1000+ 植物 / 1500 传送门。
//
// 与项目 VoxelData.glsl 的区别：ITRP 用 Ray 结构体（ori/dir/rdir/sdir），项目 DDA
// 用裸向量 —— 此处定义 VoxelRay 结构体桥接，消费端（VoxelTracing / VoxelGI.frag）
// 构建 VoxelRay 后调用 IsHitBlock。
//
// IsHitBlock（ITRP L566-579，追踪/IRC 与形状求交的桥）：
// - 全块（voxelID <= 154，含熔岩/发光/反光等普通方块）：整格命中，
//   法线 = -tracingNext * ray.sdir（DDA 进入面方向反推）
// - 形状块（155-294）：rayLength 重置为"本格退出距离"（minVec3(totalStep)，
//   光线需在退出本格前进入子盒），再做 HitShape 子盒求交；未命中返回 false
//   → 光线穿越本格子盒空隙继续步进（穿透式 DDA 语义）
// - 未移植：LightShpereColor/HitLightShpere（项目 VoxelData.glsl 已有
//   VoxelSphereHit/VoxelHitLightSphere，发射色 = 自身 albedo 而非固定色表）、
//   HitLightShpereReflection（二期镜面追踪）、Lite 版、SHOW_TODO 编译错误
//
// 依赖：VoxelMin3/VoxelMax3（VoxelData.glsl）。须在 VoxelData.glsl 之后 include。
//================================================================================================//

// 光线结构体（ITRP Ray：ori=起点、dir=单位方向、rdir=1/abs(dir)、sdir=sign(dir)）
struct VoxelRay {
    vec3 ori;
    vec3 dir;
    vec3 rdir;
    vec3 sdir;
};

// 子盒求交（照抄 ITRP IsHitBox L126-157）：
// blockOrigin = voxelCoord - ray.ori（体素空间）；boxOrigin/boxSize = 子盒在体素内的
// 相对位置/尺寸。命中条件：子盒进入距离 tEnter <= min(rayLength, tExit)（rayLength =
// 光线进入本格的距离或本格退出距离，由调用方决定语义）。命中后 rayLength = tEnter
//（子盒进入距离）、hitNormal = 命中面法线（-step(tEnter,tMin)*sdir）。
bool IsHitBox(VoxelRay ray, vec3 blockOrigin, vec3 boxOrigin, vec3 boxSize, inout float rayLength, inout vec3 hitNormal) {
    vec3 boxMin = blockOrigin + boxOrigin;
    vec3 boxMax = boxMin + boxSize;

    vec3 t1 = ray.rdir * boxMin;
    vec3 t2 = ray.rdir * boxMax;

    vec3 tMin = min(t1, t2);
    vec3 tMax = max(t1, t2);

    float tEnter = VoxelMax3(tMin);
    float tExit = VoxelMin3(tMax);

    bool hit = min(rayLength, tExit) >= tEnter && tExit >= 0.0;

    if (hit) {
        hitNormal = -step(vec3(tEnter), tMin) * ray.sdir;
        rayLength = tEnter;
    }

    return hit;
}

// 形状求交（照抄 ITRP HitShape L164-564；ID 平移：vID = voxelID - 150）。
// 形状 ID 参考全部用 vID（5-144 原表），几何公式里的 ID 系数同样用 vID。
bool HitShape(VoxelRay ray, vec3 voxelCoord, float voxelID, inout float rayLength, out vec3 hitNormal) {
    vec3 blockOrigin = voxelCoord - ray.ori;
    hitNormal = vec3(0.0);

    // 平移回 ITRP 原 ID（形状区间 155-294 → 5-144）
    float vID = voxelID - 150.0;

    bool hit = false;

    const float rotIndex[8] = float[8](1.0, 0.0, -1.0, 0.0, 0.0, 1.0, 0.0, -1.0);

    if (vID <= 8.0) { // Door

        int rotID = int(vID - 5.0);
        float rotCos = rotIndex[rotID];
        float rotSin = rotIndex[rotID + 4];
        mat2 rot = mat2(rotCos, rotSin, -rotSin, rotCos);

        vec3 ori = vec3(-0.5);
        ori.xz = ori.xz * rot;
        ori += vec3(0.5);
        vec3 size = vec3(1.0, 1.0, 3.0 / 16.0);
        size.xz = size.xz * rot;

        hit = IsHitBox(ray, blockOrigin, ori, size, rayLength, hitNormal);

    } else if (vID <= 24.0) { // Stained Glass Pane

        hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 0.0, 7.0 / 16.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal);

        if (vID >= 10.0) {
            int fenceID = int(vID - 10.0);
            int shapeID = fenceID & 3;
            int rotID = fenceID >> 2;
            float rotCos = rotIndex[rotID];
            float rotSin = rotIndex[rotID + 4];
            mat2 rot = mat2(rotCos, rotSin, -rotSin, rotCos);

            vec2 ori0 = vec2(-1.0 / 16.0, 0.0) * rot;
            ori0 += vec2(0.5);
            vec2 size0 = vec2(2.0 / 16.0, -0.5) * rot;

            vec2 ori1 = vec2(0.5, -1.0 / 16.0) * rot;
            ori1 += vec2(0.5);
            vec2 size1 = vec2(shapeID <= 1 ? -0.5 : -1.0, 2.0 / 16.0) * rot;

            if (shapeID <= 2) {
                hit = IsHitBox(ray, blockOrigin, vec3(ori0.x, 0.0, ori0.y), vec3(size0.x, 1.0, size0.y), rayLength, hitNormal) || hit;
            }
            if (shapeID >= 1) {
                hit = IsHitBox(ray, blockOrigin, vec3(ori1.x, 0.0, ori1.y), vec3(size1.x, 1.0, size1.y), rayLength, hitNormal) || hit;
            }
            if (vID == 21.0) {
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 0.0, 0.0), vec3(2.0 / 16.0, 1.0, 1.0), rayLength, hitNormal) || hit;
            }
        }

    } else if (vID <= 48.0) { // Stairs

        int stairsID = int(vID - 25.0);
        int shapeID = stairsID % 3;
        int rotID = stairsID % 12 / 3;
        float rotCos = rotIndex[rotID];
        float rotSin = rotIndex[rotID + 4];
        mat2 rot = mat2(rotCos, rotSin, -rotSin, rotCos);

        vec3 ori0 = vec3(0.0);
        vec3 size0 = vec3(1.0, 0.5, 1.0);

        vec3 ori1 = vec3(-0.5, 0.0, -0.5);
        ori1.xz = ori1.xz * rot;
        ori1 += vec3(0.5);
        vec3 size1 = vec3(1.0, 0.5, 0.5);
        size1.xz = size1.xz * rot;

        vec3 ori2 = vec3(0.5);
        vec3 size2 = vec3(-0.5, 0.5, 0.5);
        size2.xz = size2.xz * rot;

        if (stairsID >= 12) {
            ori0.y += 0.5;
            ori1.y -= 0.5;
            ori2.y -= 0.5;
        }

        hit = IsHitBox(ray, blockOrigin, ori0, size0, rayLength, hitNormal);
        if (shapeID <= 1) hit = IsHitBox(ray, blockOrigin, ori1, size1, rayLength, hitNormal) || hit;
        if (shapeID >= 1) hit = IsHitBox(ray, blockOrigin, ori2, size2, rayLength, hitNormal) || hit;

    } else if (vID <= 66.0) { // Top / Bottom Cutted

        if (vID == 53.0) { // Hopper
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 10.0 / 16.0, 0.0), vec3(2.0 / 16.0, 6.0 / 16.0, 1.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 10.0 / 16.0, 0.0), vec3(1.0, 1.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 10.0 / 16.0, 0.0), vec3(1.0, 6.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 10.0 / 16.0, 0.0), vec3(2.0 / 16.0, 6.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 10.0 / 16.0, 14.0 / 16.0), vec3(1.0, 6.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(4.0 / 16.0, 4.0 / 16.0, 4.0 / 16.0), vec3(8.0 / 16.0, 6.0 / 16.0, 8.0 / 16.0), rayLength, hitNormal) || hit;

        } else if (vID == 55.0) { // Top Trapdoor
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 13.0 / 16.0, 0.0), vec3(1.0, 3.0 / 16.0, 1.0), rayLength, hitNormal);

        } else if (vID == 59.0) { // Composter
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(2.0 / 16.0, 1.0, 1.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(1.0, 2.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 0.0, 0.0), vec3(2.0 / 16.0, 1.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 14.0 / 16.0), vec3(1.0, 1.0, 2.0 / 16.0), rayLength, hitNormal) || hit;

        } else if (vID <= 63.0) { // Top Cutted
            hit = IsHitBox(ray, blockOrigin, vec3(0.0), vec3(1.0, vID * 0.0625 - 3.0, 1.0), rayLength, hitNormal);

        } else { // Bottom Cutted
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, -vID * 0.25 + 16.75, 0.0), vec3(1.0, vID * 0.25 - 15.75, 1.0), rayLength, hitNormal);
        }

    } else if (vID <= 78.0) { // Piston / Shelf

        if (vID <= 70.0) { // Shelf
            if (vID <= 67.0) { // Shelf N
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 13.0 / 16.0), vec3(1.0, 1.0, 3.0 / 16.0), rayLength, hitNormal);
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 11.0 / 16.0), vec3(1.0, 4.0 / 16.0, 5.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 12.0 / 16.0, 11.0 / 16.0), vec3(1.0, 4.0 / 16.0, 5.0 / 16.0), rayLength, hitNormal) || hit;

            } else if (vID <= 68.0) { // Shelf W
                hit = IsHitBox(ray, blockOrigin, vec3(13.0 / 16.0, 0.0, 0.0), vec3(3.0 / 16.0, 1.0, 1.0), rayLength, hitNormal);
                hit = IsHitBox(ray, blockOrigin, vec3(11.0 / 16.0, 0.0, 0.0), vec3(5.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(11.0 / 16.0, 12.0 / 16.0, 0.0), vec3(5.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;

            } else if (vID <= 69.0) { // Shelf S
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 3.0 / 16.0), rayLength, hitNormal);
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(1.0, 4.0 / 16.0, 5.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 12.0 / 16.0, 0.0), vec3(1.0, 4.0 / 16.0, 5.0 / 16.0), rayLength, hitNormal) || hit;

            } else { // Shelf E
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(3.0 / 16.0, 1.0, 1.0), rayLength, hitNormal);
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(5.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 12.0 / 16.0, 0.0), vec3(5.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            }

        } else { // Piston
            if (vID <= 72.0) { // Piston N
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, vID * 0.5 - 35.25), vec3(1.0, 1.0, -vID * 0.5 + 36.25), rayLength, hitNormal);

            } else if (vID <= 74.0) { // Piston W
                hit = IsHitBox(ray, blockOrigin, vec3(vID * 0.5 - 36.25, 0.0, 0.0), vec3(-vID * 0.5 + 37.25, 1.0, 1.0), rayLength, hitNormal);

            } else if (vID <= 76.0) { // Piston S
                hit = IsHitBox(ray, blockOrigin, vec3(0.0), vec3(1.0, 1.0, -vID * 0.5 + 38.25), rayLength, hitNormal);

            } else { // Piston E
                hit = IsHitBox(ray, blockOrigin, vec3(0.0), vec3(-vID * 0.5 + 39.25, 1.0, 1.0), rayLength, hitNormal);
            }
        }

    } else if (vID <= 114.0) { // Wall

        if (vID == 89.0) { // Cauldron
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 0.0), vec3(2.0 / 16.0, 13.0 / 16.0, 1.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 0.0), vec3(1.0, 1.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 0.0), vec3(1.0, 13.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 3.0 / 16.0, 0.0), vec3(2.0 / 16.0, 13.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 14.0 / 16.0), vec3(1.0, 13.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;

            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(4.0 / 16.0, 3.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(12.0 / 16.0, 0.0, 0.0), vec3(4.0 / 16.0, 3.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 12.0 / 16.0), vec3(4.0 / 16.0, 3.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(12.0 / 16.0, 0.0, 12.0 / 16.0), vec3(4.0 / 16.0, 3.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;

        } else if (vID == 90.0) { // Scaffolding
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 0.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 0.0, 0.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 14.0 / 16.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 0.0, 14.0 / 16.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal) || hit;

        } else if (vID == 105.0) { // anvil NS
            hit = IsHitBox(ray, blockOrigin, vec3(2.0 / 16.0, 0.0, 2.0 / 16.0), vec3(12.0 / 16.0, 4.0 / 16.0, 12.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(4.0 / 16.0, 0.0, 3.0 / 16.0), vec3(8.0 / 16.0, 5.0 / 16.0, 10.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(6.0 / 16.0, 0.0, 4.0 / 16.0), vec3(4.0 / 16.0, 10.0 / 16.0, 8.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(3.0 / 16.0, 10.0 / 16.0, 0.0), vec3(10.0 / 16.0, 6.0 / 16.0, 1.0), rayLength, hitNormal) || hit;

        } else if (vID == 106.0) { // anvil WE
            hit = IsHitBox(ray, blockOrigin, vec3(2.0 / 16.0, 0.0, 2.0 / 16.0), vec3(12.0 / 16.0, 4.0 / 16.0, 12.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(3.0 / 16.0, 0.0, 4.0 / 16.0), vec3(10.0 / 16.0, 5.0 / 16.0, 8.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(4.0 / 16.0, 0.0, 6.0 / 16.0), vec3(8.0 / 16.0, 10.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 10.0 / 16.0, 3.0 / 16.0), vec3(1.0, 6.0 / 16.0, 10.0 / 16.0), rayLength, hitNormal) || hit;

        } else if (vID == 80.0) { // Wall None
            hit = IsHitBox(ray, blockOrigin, vec3(4.0 / 16.0, 0.0, 4.0 / 16.0), vec3(0.5, 1.0, 0.5), rayLength, hitNormal);

        } else if (vID <= 82.0) { // Wall 4
            float height = (14.0 + 2.0 * step(vID, 81.0)) / 16.0;

            hit = IsHitBox(ray, blockOrigin, vec3(5.0 / 16.0, 0.0, 0.0), vec3(6.0 / 16.0, height, 1.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 5.0 / 16.0), vec3(1.0, height, 6.0 / 16.0), rayLength, hitNormal) || hit;

        } else {
            float height = (14.0 + 2.0 * step(vID, 98.0)) / 16.0;

            int wallID = int(vID - 83.0);
            int shapeID = wallID % 16 / 4;
            int rotID = wallID % 4;
            float rotCos = rotIndex[rotID];
            float rotSin = rotIndex[rotID + 4];
            mat2 rot = mat2(rotCos, rotSin, -rotSin, rotCos);

            vec3 ori0 = vec3(-3.0 / 16.0, -0.5, -0.5);
            ori0.xz = ori0.xz * rot;
            ori0 += vec3(0.5);
            vec3 size0 = vec3(6.0 / 16.0, height, 11.0 / 16.0);
            size0.xz = size0.xz * rot;

            vec3 ori1 = vec3(0.5, -0.5, -3.0 / 16.0);
            ori1.xz = ori1.xz * rot;
            ori1 += vec3(0.5);
            vec3 size1 = vec3(shapeID <= 1 ? -1.0 : -11.0 / 16.0, height, 6.0 / 16.0);
            size1.xz = size1.xz * rot;

            if (shapeID != 1) hit = IsHitBox(ray, blockOrigin, ori0, size0, rayLength, hitNormal);
            if (shapeID != 3) hit = IsHitBox(ray, blockOrigin, ori1, size1, rayLength, hitNormal) || hit;
        }

    } else if (vID <= 142.0) { // Fence

        if (vID >= 127.0) { // Fence

            hit = IsHitBox(ray, blockOrigin, vec3(6.0 / 16.0, 0.0, 6.0 / 16.0), vec3(4.0 / 16.0, 1.0, 4.0 / 16.0), rayLength, hitNormal);

            if (vID >= 128.0) {
                int fenceID = int(vID - 128.0);
                int shapeID = fenceID % 4;
                int rotID = fenceID / 4;
                float rotCos = rotIndex[rotID];
                float rotSin = rotIndex[rotID + 4];
                mat2 rot = mat2(rotCos, rotSin, -rotSin, rotCos);

                vec2 ori0 = vec2(-1.0 / 16.0, 0.0) * rot;
                ori0 += vec2(0.5);
                vec2 size0 = vec2(2.0 / 16.0, -0.5) * rot;

                vec2 ori1 = vec2(0.5, -1.0 / 16.0) * rot;
                ori1 += vec2(0.5);
                vec2 size1 = vec2(shapeID <= 1 ? -0.5 : -1.0, 2.0 / 16.0) * rot;

                if (shapeID <= 2) {
                    hit = IsHitBox(ray, blockOrigin, vec3(ori0.x, 6.0 / 16.0, ori0.y), vec3(size0.x, 3.0 / 16.0, size0.y), rayLength, hitNormal) || hit;
                    hit = IsHitBox(ray, blockOrigin, vec3(ori0.x, 12.0 / 16.0, ori0.y), vec3(size0.x, 3.0 / 16.0, size0.y), rayLength, hitNormal) || hit;
                }
                if (shapeID >= 1) {
                    hit = IsHitBox(ray, blockOrigin, vec3(ori1.x, 6.0 / 16.0, ori1.y), vec3(size1.x, 3.0 / 16.0, size1.y), rayLength, hitNormal) || hit;
                    hit = IsHitBox(ray, blockOrigin, vec3(ori1.x, 12.0 / 16.0, ori1.y), vec3(size1.x, 3.0 / 16.0, size1.y), rayLength, hitNormal) || hit;
                }
                if (vID == 139.0) {
                    hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 6.0 / 16.0, 0.0), vec3(2.0 / 16.0, 3.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                    hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 12.0 / 16.0, 0.0), vec3(2.0 / 16.0, 3.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                }
            }

        } else if (vID <= 120.0) { // Fence Gate NS

            float heightOffset = (3.0 / 16.0) * step(vID, 117.0);
            float shapeID = mod(vID, 3.0);

            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 2.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 11.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 2.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 11.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;

            if (shapeID == 1.0) {
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(1.0, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 9.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(1.0, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(6.0 / 16.0, 3.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(4.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            } else if (shapeID == 2.0) {
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 9.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 3.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 9.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 3.0 / 16.0 + heightOffset, 1.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            } else {
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 9.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 3.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 9.0 / 16.0 + heightOffset, 7.0 / 16.0), vec3(2.0 / 16.0, 3.0 / 16.0, 0.5), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0 + heightOffset, 13.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(14.0 / 16.0, 3.0 / 16.0 + heightOffset, 13.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            }

        } else { // Fence Gate WE

            float heightOffset = (3.0 / 16.0) * step(vID, 123.0);
            float shapeID = mod(vID, 3.0);

            hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 2.0 / 16.0 + heightOffset, 0.0), vec3(2.0 / 16.0, 11.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 2.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(2.0 / 16.0, 11.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;

            if (shapeID == 1.0) {
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 3.0 / 16.0 + heightOffset, 0.0), vec3(2.0 / 16.0, 3.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 9.0 / 16.0 + heightOffset, 0.0), vec3(2.0 / 16.0, 3.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 3.0 / 16.0 + heightOffset, 6.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            } else if (shapeID == 2.0) {
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 3.0 / 16.0 + heightOffset, 0.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 9.0 / 16.0 + heightOffset, 0.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 3.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 9.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 3.0 / 16.0 + heightOffset, 0.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 3.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            } else {
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 3.0 / 16.0 + heightOffset, 0.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 9.0 / 16.0 + heightOffset, 0.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 3.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 9.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(0.5, 3.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(13.0 / 16.0, 3.0 / 16.0 + heightOffset, 0.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
                hit = IsHitBox(ray, blockOrigin, vec3(13.0 / 16.0, 3.0 / 16.0 + heightOffset, 14.0 / 16.0), vec3(2.0 / 16.0, 9.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal) || hit;
            }
        }

    } else if (abs(vID - 199.0) < 41.5) { // Light Source [158, 240]
        if (vID <= 219.0) {
            uint lichenID = uint(vID - 157.0);
            if (bool(lichenID & 32u)) { // down
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 5e-6, 0.0), vec3(1.0, 5e-6, 1.0), rayLength, hitNormal);
            }
            if (bool(lichenID & 16u)) { // up
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 1.0 - 5e-6, 0.0), vec3(1.0, 5e-6, 1.0), rayLength, hitNormal) || hit;
            }
            if (bool(lichenID & 8u)) { // north
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 5e-6), vec3(1.0, 1.0, 5e-6), rayLength, hitNormal) || hit;
            }
            if (bool(lichenID & 4u)) { // east
                hit = IsHitBox(ray, blockOrigin, vec3(1.0 - 5e-6, 0.0, 0.0), vec3(5e-6, 1.0, 1.0), rayLength, hitNormal) || hit;
            }
            if (bool(lichenID & 2u)) { // south
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 1.0 - 5e-6), vec3(1.0, 1.0, 5e-6), rayLength, hitNormal) || hit;
            }
            if (bool(lichenID & 1u)) { // west
                hit = IsHitBox(ray, blockOrigin, vec3(5e-6, 0.0, 0.0), vec3(5e-6, 1.0, 1.0), rayLength, hitNormal) || hit;
            }
        } else if (abs(vID - 223.0) < 1.5) { // End Rod
            if (vID == 222.0) { // End Rod X
                hit = IsHitBox(ray, blockOrigin, vec3(0.0, 7.0 / 16.0, 7.0 / 16.0), vec3(1.0, 2.0 / 16.0, 2.0 / 16.0), rayLength, hitNormal);

            } else if (vID == 223.0) { // End Rod Y
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 0.0, 7.0 / 16.0), vec3(2.0 / 16.0, 1.0, 2.0 / 16.0), rayLength, hitNormal);

            } else { // End Rod Z
                hit = IsHitBox(ray, blockOrigin, vec3(7.0 / 16.0, 7.0 / 16.0, 0.0), vec3(2.0 / 16.0, 2.0 / 16.0, 1.0), rayLength, hitNormal);
            }

        } else if (vID == 235.0 || vID == 237.0 || vID == 239.0) { // Campfire NS
            hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 0.0, 0.0), vec3(14.0 / 16.0, 1.0 / 16.0, 1.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 0.0, 0.0), vec3(4.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(11.0 / 16.0, 0.0, 0.0), vec3(4.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 1.0 / 16.0), vec3(1.0, 4.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 3.0 / 16.0, 11.0 / 16.0), vec3(1.0, 4.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;

        } else { // Campfire WE // 236 238 240
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 1.0 / 16.0), vec3(1.0, 1.0 / 16.0, 14.0 / 16.0), rayLength, hitNormal);
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 1.0 / 16.0), vec3(1.0, 4.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(0.0, 0.0, 11.0 / 16.0), vec3(1.0, 4.0 / 16.0, 4.0 / 16.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 3.0 / 16.0, 0.0), vec3(4.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
            hit = IsHitBox(ray, blockOrigin, vec3(11.0 / 16.0, 3.0 / 16.0, 0.0), vec3(4.0 / 16.0, 4.0 / 16.0, 1.0), rayLength, hitNormal) || hit;
        }

    } else if (vID == 143.0) { // Pressure Plate

        hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 0.0, 1.0 / 16.0), vec3(14.0 / 16.0, 1.0 / 16.0, 14.0 / 16.0), rayLength, hitNormal);

    } else if (vID == 144.0) { // Pressure Plate Powered

        hit = IsHitBox(ray, blockOrigin, vec3(1.0 / 16.0, 0.0, 1.0 / 16.0), vec3(14.0 / 16.0, 0.5 / 16.0, 14.0 / 16.0), rayLength, hitNormal);
    }

    return hit;
}

// 追踪循环与形状求交的桥（照抄 ITRP IsHitBlock L566-579）：
// - 全块（voxelID <= 154，含熔岩/发光等普通方块）：整格命中，法线 = -tracingNext*sdir
//   （DDA 进入面方向反推；rayLength 保持调用方传入的"本格进入距离"不变）
// - 形状块（155-294）：rayLength 重置为"本格退出距离"= minVec3(totalStep)
//   （光线必须在本格退出前进入子盒），HitShape 子盒求交；未命中返回 false
// totalStep/tracingNext/voxelCoord = DDA 步进状态（当前格已 advance 后的值）；
// 命中后 rayLength = 子盒进入距离、hitNormal = 子盒命中面法线。
bool IsHitBlock(VoxelRay ray, vec3 totalStep, vec3 tracingNext, vec3 voxelCoord, float voxelID, inout float rayLength, out vec3 hitNormal) {
    hitNormal = vec3(0.0);

    bool hit = true;

    if (voxelID <= 154.0) {
        hitNormal = -tracingNext * ray.sdir;
    } else {
        rayLength = VoxelMin3(totalStep);
        hit = HitShape(ray, voxelCoord, voxelID, rayLength, hitNormal);
    }

    return hit;
}
