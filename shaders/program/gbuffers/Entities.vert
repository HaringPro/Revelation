/*
--------------------------------------------------------------------------------
    Revelation Shaders
    Copyright (C) 2026 HaringPro
    Apache License 2.0
--------------------------------------------------------------------------------
*/

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

#if defined MC_NORMAL_MAP
    out mat3 tbnMatrix;
#else
    out vec3 geoNormal;
#endif

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;
out float viewDist;

//======// Attribute //===========================================================================//

in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform int entityId;
uniform mat4 gbufferModelViewInverse;
uniform vec2 taaJitter;

//======// Main //================================================================================//
void main() {
    // 顶点颜色和纹理坐标
    vertColor = gl_Color;
    texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

    // 光照贴图
    lightmap = (gl_MultiTexCoord1.xy - 8.0) * rcp(232.0);
    lightmap = clamp(lightmap, 0.0, 1.0);

    // 视图空间位置及距离
    vec3 viewPos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
    viewDist = length(viewPos);

    // 裁剪空间坐标
    gl_Position = vec4(diagonal3(gl_ProjectionMatrix) * viewPos + gl_ProjectionMatrix[3].xyz, -viewPos.z);

    #ifdef TAA_ENABLED
        gl_Position.xy += taaJitter * gl_Position.w;
    #endif

    // 法线变换（一次矩阵乘法到世界空间）
    vec3 worldNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

    #if defined MC_NORMAL_MAP
        vec3 worldTangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
        tbnMatrix[2] = worldNormal;
        tbnMatrix[0] = worldTangent;
        tbnMatrix[1] = signMul(cross(worldTangent, worldNormal), at_tangent.w);
    #else
        geoNormal = worldNormal;
    #endif

    // 材质ID
    materialID = entityId == 829925 ? 39u : uint(entityId - 10000);
}