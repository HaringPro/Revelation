#version 450 compatibility

#define DOWNSAMPLE_LEVEL 3
const vec2 workGroupsRender = vec2(0.0625f, 0.0625f);

#include "/program/post/Downsample.comp"