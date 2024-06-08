#version 450 compatibility

#define DOWNSAMPLE_LEVEL 5
const vec2 workGroupsRender = vec2(0.015625f, 0.015625f);

#include "/program/post/Downsample.comp"