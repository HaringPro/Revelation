#version 460 compatibility
#define DIMENSION_THE_END
/*
--------------------------------------------------------------------------------

    Revelation Shaders - Deferred Vertex Stage

    Copyright (C) 2026 HaringPro
    Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Output //==============================================================================//

out vec2 texCoord;
out vec3 sunDir;
out vec3 moonDir;
out vec3 worldSunDir;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 sunPosition;
uniform vec3 moonPosition;

//======// Main //================================================================================//
void main() {
    // 标准全屏四边形变换
    // gl_Vertex 通常是 (-1,-1) 到 (1,1)
    gl_Position = vec4(gl_Vertex.xy, 0.0, 1.0);
    
    // 纹理坐标映射到 [0, 1]
    texCoord = gl_Vertex.xy * 0.5 + 0.5;

    // 计算视图空间下的太阳/月亮方向 (用于后续光照计算)
    sunDir = normalize(mat3(gbufferModelView) * sunPosition);
    moonDir = normalize(mat3(gbufferModelView) * moonPosition);

    // 计算世界空间下的太阳方向 (用于大气散射)
    worldSunDir = normalize(sunPosition);
}