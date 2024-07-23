#version 450 compatibility

#include "/settings.glsl"

#if defined VOXEL_BRANCH
    #include "/lib/voxel/shadow/Shadow.vert"
#else
    #include "/program/shadow/Shadow.vert"
#endif