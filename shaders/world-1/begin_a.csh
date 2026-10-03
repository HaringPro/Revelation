#version 460 compatibility

#define CLEAR_IMAGE colorimg3
#define CLEAR_IMAGE_FORMAT image2D
#define CLEAR_COLOR vec4(0.0, 0.0, 0.0, 0.0)

#define CLEAR_IMAGE1 colorimg6
#define CLEAR_IMAGE_FORMAT1 image2D
#define CLEAR_COLOR1 vec4(0.0, 0.0, 0.0, 1.0)

#define CLEAR_IMAGE2 colorimg7
#define CLEAR_IMAGE_FORMAT2 uimage2D
#define CLEAR_COLOR2 uvec4(0)

#define CLEAR_IMAGE3 colorimg8
#define CLEAR_IMAGE_FORMAT3 image2D
#define CLEAR_COLOR3 vec4(0.0, 0.0, 0.0, 0.0)

#define CLEAR_IMAGE4 colorimg12
#define CLEAR_IMAGE_FORMAT4 image2D
#define CLEAR_COLOR4 vec4(0.0, 0.0, 0.0, 0.0)

#include "/lib/Utility.glsl"

layout(local_size_x = 16, local_size_y = 16) in;
const vec2 workGroupsRender = vec2(RENDER_SCALE, RENDER_SCALE);

#include "/program/setup/ImageClear.comp"
