#version 450 core

#define DOWNSAMPLE_LEVEL 6
const vec2 workGroupsRender = vec2(7.8125e-3f, 7.8125e-3f);

#include "/program/post/bloom/Downsample.comp"