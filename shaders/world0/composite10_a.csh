#version 460 core

// Vertical blur pass
#define OFFSET ivec2(0, 1)
layout (local_size_x = 1, local_size_y = 128) in;

#include "/program/post/bloom/Blur.comp"