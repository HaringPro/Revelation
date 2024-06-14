#version 450 compatibility

#define DOWNSAMPLE_LEVEL 1
const vec2 workGroupsRender = vec2(0.25f, 0.25f);

#include "/program/post/bloom/Downsample.comp"