layout (local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
const ivec3 workGroups = ivec3(4, 2, 4);

#include "/lib/Utility.glsl"
#include "/lib/universal/Uniform.glsl"

// 体素网格参数（跟随玩家）
const ivec3 voxelGridSize = ivec3(16, 8, 16);
const float voxelSize = 4.0;

layout (r11f_g11f_b10f) restrict uniform image2D colorimg15;

void main() {
    ivec3 voxelCoord = ivec3(gl_GlobalInvocationID.xyz);
    if (any(greaterThanEqual(voxelCoord, voxelGridSize))) return;

    // 以玩家为中心的网格原点
    vec3 gridOrigin = cameraPosition - vec3(voxelGridSize) * voxelSize * 0.5;
    vec3 worldPos = gridOrigin + vec3(voxelCoord) * voxelSize + voxelSize * 0.5;

    vec4 clipPos = gbufferProjection * gbufferModelView * vec4(worldPos, 1.0);
    if (clipPos.w <= 0.0) return;
    vec3 ndc = clipPos.xyz / clipPos.w;
    vec2 screenCoord = ndc.xy * 0.5 + 0.5;

    if (screenCoord.x < 0.0 || screenCoord.x > 1.0 || screenCoord.y < 0.0 || screenCoord.y > 1.0) return;

    vec3 newGI = textureLod(colortex3, screenCoord, 0.0).rgb;

    int index = voxelCoord.x + voxelCoord.y * voxelGridSize.x + voxelCoord.z * voxelGridSize.x * voxelGridSize.y;
    ivec2 storeCoord = ivec2(index % 256, index / 256);

    vec3 oldGI = imageLoad(colorimg15, storeCoord).rgb;
    vec3 mixedGI = mix(newGI, oldGI, 0.9);
    imageStore(colorimg15, storeCoord, vec4(mixedGI, 1.0));
}