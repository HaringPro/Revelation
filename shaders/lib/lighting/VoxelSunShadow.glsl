//================================================================================================//
// Voxel Sun Shadow — 参考实现 阳光 GI 阴影判定移植（2026-08-09）
//
// 参考 参考实现 Lib/PathTracing/Tracer/ShadowTracing.glsl：
// - VoxelSunShadowMap：实时阴影贴图判定（参考实现 SimpleShadow 简化移植）——
//   命中点世界坐标 → 阴影贴图屏幕坐标（失真 + 体素平铺 Shift），沿命中面法线
//   做微小屏幕偏移避免体素表面自阴影（阴影边缘 0/1 跳变 → 块状闪烁/漏光），
//   shadowtex1 硬件深度比较。
// - VoxelSunShadowTracing：体素 DDA 短程遮挡判定（参考实现 SimpleShadowTracing 移植）——
//   从命中体素向太阳方向步进 3 格，撞到固体/形状 → 0（阳光被挡）。
//   捕捉阴影贴图分辨率外的网格内小遮挡（屋檐/树冠缝隙/墙角）。
//
// 依赖：VoxelData.glsl + VoxelShape.glsl（VoxelMin3/VoxelRay/IsHitBlock）、
//       shadow/Common.glsl（DistortShadowSpace）、VoxelLighting.glsl（ShiftShadowScreenPos），
//       调用方须已声明 uniform sampler2DShadow shadowtex1（本文件补充 shadowtex0/shadowcolor0）。
//================================================================================================//

uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;

// 实时阴影贴图判定（参考实现 SimpleShadow 移植，去 RTW warp）：
// 返回彩色阴影 vec3——1=全亮直射；0=被实心挡；穿过半透明物体（玻璃）时
// = AlbedoToAbsorption(玻璃颜色, 不透明度)，反弹光线带上玻璃染色。
vec3 VoxelSunShadowMap(vec3 camRelPos, vec3 normal) {
    vec3 result = vec3(1.0);
    if (sunPosition.y < 0.01) return vec3(0.0);
    vec3 shadowClipPos = (shadowModelView * vec4(camRelPos, 1.0)).xyz;
    shadowClipPos = (shadowProjection * vec4(shadowClipPos, 1.0)).xyz;
    vec3 ssp = DistortShadowSpace(shadowClipPos) * 0.5 + 0.5;
    #ifdef ENABLE_VOXELIZATION
        ShiftShadowScreenPos(ssp.xy);
    #endif
    // 沿阴影空间命中法线做微小屏幕偏移（参考实现 SimpleShadow NDC 0.00025 ≈ 屏幕 0.000125），
    // 避免体素命中面自阴影导致 sunVis 恒 0（阴影边缘块状闪烁/漏光）
    ssp.xy += (mat3(shadowModelView) * normal).xy * 0.000125;
    if (all(equal(ssp, saturate(ssp)))) {
        result = vec3(0.0);
        ssp.z -= 4e-5;

        // 实心深度（shadowtex1，sampler2DShadow 硬件深度比较）：vec3 = xy + 参考深度，
        // 返回值即可见性（1=未被实心挡，0=被挡），无需再 step
        float soildShadow = textureLod(shadowtex1, vec3(ssp.xy, ssp.z), 0.0);
        if (soildShadow > 0.5) {
            // 透明深度（shadowtex0）：没被透明物体挡 → 全亮
            float translucentShadow = step(ssp.z, textureLod(shadowtex0, ssp.xy, 0.0).x);
            result += vec3(translucentShadow);

            // 被透明物体（玻璃）挡住的部分 → 采样颜色，按不透明度算吸收色
            float coloredShadow = saturate(soildShadow - translucentShadow);
            if (coloredShadow > 1e-3) {
                vec4 shadowColorSample = textureLod(shadowcolor0, ssp.xy, 0.0);
                if (shadowColorSample.a > 0.003) {
                    shadowColorSample.rgb = VoxelAlbedoToAbsorption(sRGBToLinear(shadowColorSample.rgb), shadowColorSample.a);
                    result += shadowColorSample.rgb * coloredShadow;
                }
                // 水吸收分支省略：当前项目 shadowcolor0 不写水数据（水走 shadowcolor1）
            }
        }
    }
    return result;
}

// 体素 DDA 短程阳光遮挡判定（参考实现 SimpleShadowTracing）：1=阳光可见，0=被网格内固体挡住
float VoxelSunShadowTracing(vec3 voxelPos, vec3 sunDir) {
    vec3 voxelCoord = floor(voxelPos);
    vec3 sdir = sign(sunDir);
    vec3 rdir = 1.0 / max(abs(sunDir), vec3(1e-8));
    vec3 totalStep = (sdir * (voxelCoord - voxelPos + 0.5) + 0.5) * rdir;
    for (int i = 0; i < 3; ++i) {
        // 先步进到下一格（起点格是命中固体本身，不算遮挡）
        float rayLength = VoxelMin3(totalStep);
        vec3 tracingNext = step(totalStep, vec3(rayLength));
        voxelCoord += tracingNext * sdir;
        totalStep += tracingNext * rdir;
        if (any(lessThan(voxelCoord, vec3(0.0))) || any(greaterThanEqual(voxelCoord, vec3(float(VOXEL_AREA))))) break;

        vec4 hvd = texelFetch(voxelDataSampler, ivec3(voxelCoord), 0);
        if (hvd.z > 0.5) {
            VoxelRay vray;
            vray.ori = voxelPos;
            vray.dir = sunDir;
            vray.rdir = rdir;
            vray.sdir = sdir;
            vec3 hitNormal;
            float hitLength = rayLength;
            if (IsHitBlock(vray, totalStep, tracingNext, voxelCoord, abs(hvd.z), hitLength, hitNormal)) {
                return 0.0;
            }
        }
    }
    return 1.0;
}
