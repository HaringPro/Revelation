#version 450 compatibility

#define DOWNSAMPLE_LEVEL 2
const vec2 workGroupsRender = vec2(0.125f, 0.125f);

#include "/program/post/bloom/Downsample.comp"