#version 450 core

#define DOWNSAMPLE_LEVEL 4
const vec2 workGroupsRender = vec2(0.03125f, 0.03125f);

#include "/program/post/bloom/Downsample.comp"