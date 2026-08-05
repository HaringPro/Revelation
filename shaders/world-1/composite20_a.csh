#version 460 compatibility

// Horizontal blur pass
#define OFFSET ivec2(1, 0)
layout (local_size_x = 128, local_size_y = 1) in;

#include "/program/post/bloom/Blur.comp"