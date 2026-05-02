#version 460 compatibility

#define CLEAR_IMAGE skyMapImg
#define CLEAR_COLOR vec4(0.0)

layout (local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(16, 16, 1);

#include "/program/setup/ImageClear.comp"
